#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
"""
Complete NCCL to CSV Converter
Parses NCCL output and creates CSV files with results and summary
"""

import re
import csv
import sys
from pathlib import Path

def parse_nccl_output(file_path):
    """Parse NCCL test output and extract performance data"""
    
    data = []
    avg_bandwidth = None
    
    # Pattern to match NCCL performance lines (flexible for different test types)
    # Handles both allreduce/reducescatter format and allgather/alltoall format
    # Note: alltoall uses N/A for in-place errors, so we handle that case
    pattern = r'^\s*(\d+)\s+(\d+)\s+(float|double|int|half)\s+(sum|prod|max|min|none)\s+(-?\d+)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+|N/A)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+|N/A)'
    
    # Pattern to match average bandwidth line
    avg_pattern = r'# Avg bus bandwidth\s*:\s*(\d+\.?\d*)'
    
    try:
        with open(file_path, 'r') as f:
            for line_num, line in enumerate(f, 1):
                # Check for performance data
                match = re.match(pattern, line.strip())
                if match:
                    size_bytes = int(match.group(1))
                    count = int(match.group(2))
                    data_type = match.group(3)
                    operation = match.group(4)
                    root = int(match.group(5))
                    
                    # Out-of-place metrics
                    oop_time_us = float(match.group(6))
                    oop_algbw = float(match.group(7))
                    oop_busbw = float(match.group(8))
                    oop_error = 0 if match.group(9) == 'N/A' else int(match.group(9))
                    
                    # In-place metrics  
                    ip_time_us = float(match.group(10))
                    ip_algbw = float(match.group(11))
                    ip_busbw = float(match.group(12))
                    ip_error = 0 if match.group(13) == 'N/A' else int(match.group(13))
                    
                    data.append({
                        'Size_Bytes': size_bytes,
                        'Size_KB': round(size_bytes / 1024, 2),
                        'Size_MB': round(size_bytes / (1024 * 1024), 2),
                        'Count': count,
                        'Data_Type': data_type,
                        'Operation': operation,
                        'Root': root,
                        'OOP_Time_us': oop_time_us,
                        'OOP_AlgBW_GBps': oop_algbw,
                        'OOP_BusBW_GBps': oop_busbw,
                        'OOP_Errors': oop_error,
                        'IP_Time_us': ip_time_us,
                        'IP_AlgBW_GBps': ip_algbw,
                        'IP_BusBW_GBps': ip_busbw,
                        'IP_Errors': ip_error
                    })
                
                # Check for average bandwidth
                avg_match = re.search(avg_pattern, line)
                if avg_match:
                    avg_bandwidth = float(avg_match.group(1))
    
    except FileNotFoundError:
        print(f"Error: File {file_path} not found")
        return None, None
    except Exception as e:
        print(f"Error reading file: {e}")
        return None, None
    
    if not data:
        print("No NCCL performance data found in the file")
        return None, None
        
    return data, avg_bandwidth

def write_csv(data, filename):
    """Write data to CSV file"""
    
    if not data:
        return False
    
    try:
        with open(filename, 'w', newline='') as csvfile:
            fieldnames = list(data[0].keys())
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(data)
        return True
    except Exception as e:
        print(f"Error writing CSV file {filename}: {e}")
        return False

def create_summary_data(data, avg_bandwidth=None):
    """Create summary statistics from performance data"""
    
    if not data:
        return None
        
    oop_busbw_values = [row['OOP_BusBW_GBps'] for row in data]
    ip_busbw_values = [row['IP_BusBW_GBps'] for row in data]
    
    summary_data = [
        {'Metric': 'Total Test Points', 'Value': len(data)},
        {'Metric': 'Min Message Size (Bytes)', 'Value': min(row['Size_Bytes'] for row in data)},
        {'Metric': 'Max Message Size (Bytes)', 'Value': max(row['Size_Bytes'] for row in data)},
        {'Metric': 'Peak OOP Bus BW (GB/s)', 'Value': round(max(oop_busbw_values), 2)},
        {'Metric': 'Peak IP Bus BW (GB/s)', 'Value': round(max(ip_busbw_values), 2)},
        {'Metric': 'Avg OOP Bus BW (GB/s)', 'Value': round(sum(oop_busbw_values) / len(oop_busbw_values), 2)},
        {'Metric': 'Avg IP Bus BW (GB/s)', 'Value': round(sum(ip_busbw_values) / len(ip_busbw_values), 2)},
        {'Metric': 'Total Errors', 'Value': sum(row['OOP_Errors'] + row['IP_Errors'] for row in data)}
    ]
    
    if avg_bandwidth is not None:
        summary_data.append({'Metric': 'NCCL Reported Avg Bus BW (GB/s)', 'Value': avg_bandwidth})
    
    return summary_data

def main():
    if len(sys.argv) != 2:
        print("Usage: python nccl_to_excel.py <nccl_output_file>")
        print("Example: python nccl_to_excel.py nccl-tests-container_3480.out")
        sys.exit(1)
    
    input_file = sys.argv[1]
    base_name = Path(input_file).stem
    
    print(f"Parsing NCCL output from: {input_file}")
    
    # Parse the NCCL output
    data, avg_bandwidth = parse_nccl_output(input_file)
    
    if data is None:
        sys.exit(1)
    
    print(f"Found {len(data)} performance data points")
    if avg_bandwidth:
        print(f"Average bus bandwidth: {avg_bandwidth} GB/s")
    
    # Create main results CSV file
    results_file = f"{base_name}_results.csv"
    if write_csv(data, results_file):
        print(f"Results exported to: {results_file}")
    else:
        print("Error writing results file")
        sys.exit(1)
    
    # Create summary CSV file
    summary_data = create_summary_data(data, avg_bandwidth)
    if summary_data:
        summary_file = f"{base_name}_summary.csv"
        if write_csv(summary_data, summary_file):
            print(f"Summary exported to: {summary_file}")
        else:
            print("Error writing summary file")
    
    print("\nFiles created:")
    print(f"- {results_file} (detailed performance data)")
    print(f"- {summary_file} (summary statistics)")
    print("\nYou can open these CSV files in Excel, LibreOffice Calc, or any spreadsheet application")

if __name__ == "__main__":
    main()