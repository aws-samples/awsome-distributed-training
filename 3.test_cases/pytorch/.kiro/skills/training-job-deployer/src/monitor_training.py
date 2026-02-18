#!/usr/bin/env python3
"""
Auto-restart Ray training job on failure
Run this locally to monitor and auto-restart training
"""

import subprocess
import time
import sys
import re
from datetime import datetime

class TrainingMonitor:
    def __init__(self):
        self.head_pod = "verl-grpo-training-head-cjcqr"
        self.checkpoint_dir = "/checkpoints/GRPO/verl-grpo-training"
        self.max_retries = 10
        self.retry_delay = 60
        self.check_interval = 30
        self.retry_count = 0
        
    def log(self, msg, level="INFO"):
        colors = {"INFO": "\033[92m", "WARN": "\033[93m", "ERROR": "\033[91m", "RESET": "\033[0m"}
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"{colors.get(level, colors['INFO'])}[{level}]{colors['RESET']} {ts} - {msg}")
        
    def run_kubectl(self, cmd, timeout=30):
        """Run kubectl command"""
        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=timeout
            )
            return result.returncode == 0, result.stdout, result.stderr
        except Exception as e:
            return False, "", str(e)
            
    def get_latest_checkpoint(self):
        """Get latest checkpoint step"""
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {self.head_pod} -- ls -1 {self.checkpoint_dir}'
        )
        
        if not success:
            return None, 0
            
        steps = []
        for line in stdout.strip().split('\n'):
            if line.startswith('global_step_'):
                try:
                    step = int(line.replace('global_step_', ''))
                    steps.append(step)
                except:
                    pass
                    
        if steps:
            latest = max(steps)
            return f"{self.checkpoint_dir}/global_step_{latest}", latest
        return None, 0
        
    def submit_job(self, checkpoint=None):
        """Submit training job"""
        self.log("Submitting training job...")
        
        if checkpoint:
            self.log(f"Resuming from: {checkpoint}")
            resume_args = f'trainer.resume_mode=auto trainer.resume_from_path="{checkpoint}"'
        else:
            self.log("Starting from scratch")
            resume_args = ""
            
        # Build command
        cmd = f'''kubectl exec {self.head_pod} -- bash -c '
export RAY_DATA_HOME="/checkpoints"
cd /workspace/verl
ray job submit --no-wait --working-dir "/workspace/verl" -- python3 -m verl.trainer.main_ppo algorithm.adv_estimator=grpo data.train_files="/checkpoints/data/gsm8k/train.parquet" data.val_files="/checkpoints/data/gsm8k/test.parquet" data.prompt_key=question data.train_batch_size=8 data.max_prompt_length=512 data.max_response_length=1024 data.filter_overlong_prompts=True data.truncation=error actor_rollout_ref.model.path="Qwen/Qwen2.5-0.5B" actor_rollout_ref.model.use_remove_padding=True actor_rollout_ref.model.enable_gradient_checkpointing=True actor_rollout_ref.actor.optim.lr=1e-6 actor_rollout_ref.actor.ppo_mini_batch_size=8 actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=1 actor_rollout_ref.actor.use_kl_loss=True actor_rollout_ref.actor.kl_loss_coef=0.001 actor_rollout_ref.actor.kl_loss_type=low_var_kl actor_rollout_ref.actor.entropy_coeff=0 actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=32 actor_rollout_ref.rollout.tensor_model_parallel_size=2 actor_rollout_ref.rollout.name=vllm actor_rollout_ref.rollout.gpu_memory_utilization=0.6 actor_rollout_ref.rollout.n=2 actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=32 actor_rollout_ref.ref.fsdp_config.param_offload=True algorithm.use_kl_in_reward=False trainer.critic_warmup=0 trainer.logger="[console]" trainer.project_name="GRPO" trainer.experiment_name="verl-grpo-training" trainer.n_gpus_per_node=1 trainer.nnodes=4 trainer.default_local_dir="{self.checkpoint_dir}" trainer.save_freq=10 trainer.test_freq=2 trainer.total_epochs=2 {resume_args}
' 2>&1 | grep "Job '\" | head -1'''
        
        success, stdout, stderr = self.run_kubectl(cmd, timeout=60)
        
        if success and 'raysubmit_' in stdout:
            # Extract job ID
            match = re.search(r"raysubmit_[a-zA-Z0-9]+", stdout)
            if match:
                return match.group(0)
                
        self.log(f"Failed to submit job: {stdout} {stderr}", "ERROR")
        return None
        
    def check_status(self, job_id):
        """Check job status"""
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {self.head_pod} -- ray job status {job_id}'
        )
        
        if success:
            for line in stdout.split('\n'):
                if 'Status' in line:
                    return line.split(':')[1].strip()
        return "UNKNOWN"
        
    def get_current_step(self, job_id):
        """Get current step from logs"""
        success, stdout, stderr = self.run_kubectl(
            f'kubectl exec {self.head_pod} -- ray job logs {job_id} 2>&1 | grep "step:" | tail -1'
        )
        
        if success:
            match = re.search(r'step:(\d+)', stdout)
            if match:
                return int(match.group(1))
        return 0
        
    def monitor_job(self, job_id):
        """Monitor job until completion or failure"""
        self.log(f"Monitoring job: {job_id}")
        last_step = 0
        stagnation = 0
        
        while True:
            time.sleep(self.check_interval)
            
            status = self.check_status(job_id)
            self.log(f"Status: {status}")
            
            if status == "SUCCEEDED":
                return True
                
            if status in ["FAILED", "STOPPED"]:
                return False
                
            if status == "RUNNING":
                step = self.get_current_step(job_id)
                if step > last_step:
                    self.log(f"Progress: Step {step}")
                    last_step = step
                    stagnation = 0
                else:
                    stagnation += 1
                    if stagnation >= 20:
                        self.log("No progress for 10 minutes!", "WARN")
                        
    def run(self):
        """Main loop"""
        self.log("=" * 60)
        self.log("Auto-Restart Training Monitor")
        self.log("=" * 60)
        
        while self.retry_count < self.max_retries:
            self.retry_count += 1
            self.log(f"Attempt {self.retry_count}/{self.max_retries}")
            
            # Get checkpoint
            checkpoint, step = self.get_latest_checkpoint()
            if checkpoint:
                self.log(f"Found checkpoint at step {step}")
            
            # Submit job
            job_id = self.submit_job(checkpoint)
            if not job_id:
                time.sleep(self.retry_delay)
                continue
                
            self.log(f"Job ID: {job_id}")
            
            # Monitor
            if self.monitor_job(job_id):
                self.log("Training completed!")
                return 0
            else:
                self.log("Job failed, restarting...", "WARN")
                time.sleep(self.retry_delay)
                
        self.log("Max retries reached", "ERROR")
        return 1

if __name__ == "__main__":
    monitor = TrainingMonitor()
    try:
        sys.exit(monitor.run())
    except KeyboardInterrupt:
        monitor.log("Interrupted", "WARN")
        sys.exit(130)
