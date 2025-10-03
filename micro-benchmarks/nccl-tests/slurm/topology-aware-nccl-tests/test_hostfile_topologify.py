#!/usr/bin/env python3
"""
Test suite for hostfile-topologify.py script
"""

import pytest
import tempfile
import os
import sys
import importlib.util
import time
from unittest.mock import Mock, patch, MagicMock
from io import StringIO

# Import the module under test
import hostfile_topologify


class TestHostfileTopologify:
    """Test cases for hostfile-topologify.py"""

    @pytest.fixture
    def mock_ec2_responses(self):
        """Mock EC2 API responses"""
        # Mock describe_instances response
        describe_instances_response = {
            'Reservations': [
                {
                    'Instances': [
                        {
                            'InstanceId': 'i-1example',
                            'NetworkInterfaces': [
                                {'PrivateIpAddress': '10.0.1.1'}
                            ]
                        },
                        {
                            'InstanceId': 'i-2example',
                            'NetworkInterfaces': [
                                {'PrivateIpAddress': '10.0.1.2'}
                            ]
                        },
                        {
                            'InstanceId': 'i-3example',
                            'NetworkInterfaces': [
                                {'PrivateIpAddress': '10.0.1.3'}
                            ]
                        },
                        {
                            'InstanceId': 'i-4example',
                            'NetworkInterfaces': [
                                {'PrivateIpAddress': '10.0.1.4'}
                            ]
                        }
                    ]
                }
            ]
        }

        # Mock describe_instance_topology response
        describe_topology_response = {
            "Instances": [
                {
                    "InstanceId": "i-1example",
                    "InstanceType": "p5en.48xlarge",
                    "GroupName": "ML-group",
                    "NetworkNodes": [
                        "nn-1example",
                        "nn-2example",
                        "nn-4example"
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                },
                {
                    "InstanceId": "i-2example",
                    "InstanceType": "p5en.48xlarge",
                    "NetworkNodes": [
                        "nn-1example",
                        "nn-2example",
                        "nn-4example"
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                },
                {
                    "InstanceId": "i-3example",
                    "InstanceType": "p5en.48xlarge",
                    "NetworkNodes": [
                        "nn-1example",
                        "nn-2example",
                        "nn-5example"
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                },
                {
                    "InstanceId": "i-4example",
                    "InstanceType": "p5en.48xlarge",
                    "NetworkNodes": [
                        "nn-1example",
                        "nn-3example",
                        "nn-6example"
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                }
            ]
        }

        return {
            'describe_instances': describe_instances_response,
            'describe_topology': describe_topology_response
        }

    @patch('time.sleep')
    def test_topology_based_ordering(self, mock_sleep, mock_ec2_responses):
        """Test that hosts are output in topology-aware order for optimal placement"""
        
        # Add extra newline at the end to ensure proper EOF handling
        sample_content = "host-1\nhost-2\nhost-3\nhost-4\n\n"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as input_file:
            input_file.write(sample_content)
            input_file_path = input_file.name

        try:
            def mock_gethostbyname(hostname):
                hostname_to_ip_map = {
                    'host-1': '10.0.1.1',
                    'host-2': '10.0.1.2', 
                    'host-3': '10.0.1.3',
                    'host-4': '10.0.1.4'
                }
                return hostname_to_ip_map.get(hostname, '127.0.0.1')

            mock_ec2_client = Mock()
            mock_ec2_client.describe_instances.return_value = mock_ec2_responses['describe_instances']
            mock_ec2_client.describe_instance_topology.return_value = mock_ec2_responses['describe_topology']

            output_buffer = StringIO()

            with patch('socket.gethostbyname', side_effect=mock_gethostbyname), \
                 patch('socket.getfqdn', side_effect=lambda x: x), \
                 patch('boto3.client', return_value=mock_ec2_client):

                with open(input_file_path, 'r') as input_handle:
                    hostfile_topologify.generate_topology_csv(
                        input_handle, 
                        output_buffer, 
                        'us-west-2'
                    )

            # Verify that describe_instance_topology was called with the expected instance IDs
            topology_call_args = mock_ec2_client.describe_instance_topology.call_args
            called_instance_ids = set(topology_call_args[1]['InstanceIds'])
            expected_instance_ids = {
                'i-1example', 
                'i-2example', 
                'i-3example', 
                'i-4example'
            }
            
            # This is the key test - verify the expected instance IDs are processed
            assert called_instance_ids == expected_instance_ids, f"Expected {expected_instance_ids}, got {called_instance_ids}"

            # Verify output contains all hostnames in topology-sorted order
            output_lines = output_buffer.getvalue().strip().split('\n')
            output_lines = [line for line in output_lines if line]
            assert len(output_lines) == 4
            
            # The output should be ordered by topology: t2_node -> t1_node -> hostname
            # Based on the mock topology data:
            # - host-1 and host-2 share nn-2example (t2) and nn-4example (t1)
            # - host-3 has nn-2example (t2) and nn-5example (t1) 
            # - host-4 has nn-3example (t2) and nn-6example (t1)
            # Expected order: hosts with same t2/t1 should be grouped together
            expected_hostnames = ['host-1', 'host-2', 'host-3', 'host-4']
            assert output_lines == expected_hostnames, f"Expected order {expected_hostnames}, got {output_lines}"

        finally:
            os.unlink(input_file_path)

    @patch('time.sleep')
    def test_empty_hostfile(self, mock_sleep):
        """Test handling of empty hostfile"""
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as input_file:
            input_file.write("")  # Completely empty file
            input_file_path = input_file.name

        try:
            mock_ec2_client = Mock()
            output_buffer = StringIO()

            with patch('boto3.client', return_value=mock_ec2_client):
                with open(input_file_path, 'r') as input_handle:
                    hostfile_topologify.generate_topology_csv(
                        input_handle, 
                        output_buffer, 
                        'us-west-2'
                    )

            # Should produce no output for empty input
            assert output_buffer.getvalue().strip() == ""
            # EC2 client should not be called for empty input
            mock_ec2_client.describe_instances.assert_not_called()

        finally:
            os.unlink(input_file_path)

    @patch('time.sleep')
    def test_pagination_with_topology_ordering(self, mock_sleep):
        """Test pagination handling with topology-based ordering for large hostfiles (>64 hosts)"""
        
        # Create 70 hosts to trigger pagination (pagination_count = 64)
        num_hosts = 70
        hostfile_content = "\n".join([f"host-{i}" for i in range(1, num_hosts + 1)]) + "\n"
        
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as input_file:
            input_file.write(hostfile_content)
            input_file_path = input_file.name

        try:
            def mock_gethostbyname(hostname):
                if not hostname or not hostname.startswith('host-'):
                    raise Exception(f"Invalid hostname: '{hostname}'")
                # Extract number from hostname and create IP
                host_num = int(hostname.split('-')[1])
                # Ensure IP doesn't exceed 255 in any octet
                return f"10.0.{(host_num - 1) // 254 + 1}.{(host_num - 1) % 254 + 1}"

            # Create mock responses for pagination
            # First batch: instances 1-64
            first_batch_instances = []
            first_batch_topology = []
            
            for i in range(1, 65):  # 1-64
                first_batch_instances.append({
                    'InstanceId': f'i-{i}example',
                    'NetworkInterfaces': [
                        {'PrivateIpAddress': f'10.0.{(i - 1) // 254 + 1}.{(i - 1) % 254 + 1}'}
                    ]
                })
                first_batch_topology.append({
                    "InstanceId": f"i-{i}example",
                    "InstanceType": "p5en.48xlarge",
                    "GroupName": "ML-group",
                    "NetworkNodes": [
                        "nn-1example",                    # Level 1: Only one node for all instances
                        f"nn-{(i - 1) % 2 + 2}example",  # Level 2: Rotate between nn-2example and nn-3example
                        f"nn-{i + 3}example"              # Level 3: Unique nodes starting from nn-4example
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                })

            # Second batch: instances 65-70
            second_batch_instances = []
            second_batch_topology = []
            
            for i in range(65, 71):  # 65-70
                second_batch_instances.append({
                    'InstanceId': f'i-{i}example',
                    'NetworkInterfaces': [
                        {'PrivateIpAddress': f'10.0.{(i - 1) // 254 + 1}.{(i - 1) % 254 + 1}'}
                    ]
                })
                second_batch_topology.append({
                    "InstanceId": f"i-{i}example",
                    "InstanceType": "p5en.48xlarge",
                    "GroupName": "ML-group",
                    "NetworkNodes": [
                        "nn-1example",                    # Level 1: Only one node for all instances
                        f"nn-{(i - 1) % 2 + 2}example",  # Level 2: Rotate between nn-2example and nn-3example
                        f"nn-{i + 3}example"              # Level 3: Unique nodes starting from nn-4example
                    ],
                    "CapacityBlockId": "null",
                    "ZoneId": "usw2-az2",
                    "AvailabilityZone": "us-west-2a"
                })

            # Debug: Output combined topology data to JSON file
            import json
            combined_topology = first_batch_topology + second_batch_topology
            with open('debug_topology.json', 'w') as debug_file:
                json.dump(combined_topology, debug_file, indent=2)
            

            mock_ec2_client = Mock()
            
            # The original code processes hosts in batches of 64, so we need to simulate
            # separate API calls for each batch. Each call to describe_instances and 
            # describe_instance_topology will be for a specific batch of instances.
            
            call_count = {'describe_instances': 0, 'describe_topology': 0}
            
            def mock_describe_instances(**kwargs):
                call_count['describe_instances'] += 1
                ips_requested = set(kwargs['Filters'][0]['Values'])
                
                # Determine which batch this call is for based on IPs
                first_batch_ips = {f'10.0.{(i - 1) // 254 + 1}.{(i - 1) % 254 + 1}' for i in range(1, 65)}
                second_batch_ips = {f'10.0.{(i - 1) // 254 + 1}.{(i - 1) % 254 + 1}' for i in range(65, 71)}
                
                if ips_requested.intersection(first_batch_ips):
                    return {
                        'Reservations': [{'Instances': first_batch_instances}]
                    }
                else:
                    return {
                        'Reservations': [{'Instances': second_batch_instances}]
                    }
            
            def mock_describe_topology(**kwargs):
                call_count['describe_topology'] += 1
                instance_ids_requested = set(kwargs['InstanceIds'])
                
                # Determine which batch this call is for based on instance IDs
                first_batch_ids = {f'i-{i}example' for i in range(1, 65)}
                second_batch_ids = {f'i-{i}example' for i in range(65, 71)}
                
                if instance_ids_requested.intersection(first_batch_ids):
                    return {
                        "Instances": first_batch_topology
                    }
                else:
                    return {
                        "Instances": second_batch_topology
                    }
            
            mock_ec2_client.describe_instances.side_effect = mock_describe_instances
            mock_ec2_client.describe_instance_topology.side_effect = mock_describe_topology

            output_buffer = StringIO()

            with patch('socket.gethostbyname', side_effect=mock_gethostbyname), \
                 patch('socket.getfqdn', side_effect=lambda x: x), \
                 patch('boto3.client', return_value=mock_ec2_client):

                with open(input_file_path, 'r') as input_handle:
                    hostfile_topologify.generate_topology_csv(
                        input_handle, 
                        output_buffer, 
                        'us-west-2'
                    )

            # Verify pagination was triggered (multiple calls made)
            # The script processes hosts in batches of 64, so we should see 2 iterations
            assert call_count['describe_instances'] == 2, f"Should make 2 calls to describe_instances, got {call_count['describe_instances']}"
            assert call_count['describe_topology'] == 2, f"Should make 2 calls to describe_instance_topology, got {call_count['describe_topology']}"

            # Verify output contains all hostnames in topology-sorted order
            output_lines = output_buffer.getvalue().strip().split('\n')
            output_lines = [line for line in output_lines if line]
            
            # Should have all 70 hostnames
            assert len(output_lines) == num_hosts
            
            # Verify all expected hostnames are present
            expected_hostnames = [f'host-{i}' for i in range(1, num_hosts + 1, 2)] + [f'host-{i}' for i in range(2, num_hosts + 1, 2)]  
            assert output_lines == expected_hostnames, f"Expected exact order {expected_hostnames}, got {output_lines}"
            
            # Verify topology-based ordering: hosts should be grouped by their network topology
            # With the new topology structure:
            # - All instances share nn-1example (level 1)
            # - Level 2 alternates between nn-2example and nn-3example
            # - Level 3 is unique per instance
            # The script groups by t2_node (level 2) then t1_node (level 3)
            
            # Hosts should be grouped by their level 2 network node (nn-2example vs nn-3example)
            nn2_hosts = []  # Hosts with nn-2example at level 2 (odd instances: 1,3,5,...)
            nn3_hosts = []  # Hosts with nn-3example at level 2 (even instances: 2,4,6,...)
            
            for line in output_lines:
                host_num = int(line.split('-')[1])
                if (host_num - 1) % 2 == 0:  # Odd instances use nn-2example
                    nn2_hosts.append(line)
                else:  # Even instances use nn-3example
                    nn3_hosts.append(line)
            
            # Verify that hosts are grouped by topology (all nn-2 hosts together, then all nn-3 hosts)
            # The exact order within groups may vary, but groups should be contiguous
            first_group_end = len(nn2_hosts) if output_lines[0] in nn2_hosts else len(nn3_hosts)
            first_group = output_lines[:first_group_end]
            second_group = output_lines[first_group_end:]
            
            # Check that each group contains only hosts from the same topology level
            if output_lines[0] in nn2_hosts:
                assert all(host in nn2_hosts for host in first_group), "First group should contain only nn-2example hosts"
                assert all(host in nn3_hosts for host in second_group), "Second group should contain only nn-3example hosts"
            else:
                assert all(host in nn3_hosts for host in first_group), "First group should contain only nn-3example hosts"
                assert all(host in nn2_hosts for host in second_group), "Second group should contain only nn-2example hosts"
            
        finally:
            os.unlink(input_file_path)




if __name__ == "__main__":
    pytest.main([__file__])