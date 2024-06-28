Quick Test for Llama3-70B

For Llama 3 70B, there are a few small things you need to do:

* update the config to the latest Llama 3 config. Be sure to add the NxD params sequence_parallel_enabled, selective_checkpoint_enabled, and move_model_to_device
* to access the tokenizer, you might need to upgrade to the latest version of transformers and tokenizers. If you do upgrade, make sure to downgrade back to transformers==4.31 before running training.
* run your data prep again with the new tokenizer, as the tokens are different, in particular the special tokens like EOS.
* Other than that, you should be able to use the same config as our public Llama 2 70B example (TP=32, PP=4, KV replication=4). Note that for now, we can’t go larger than 4096 sequence length, even though the new model supports up to 8k. → NKI support is required.

Download llama3 model (for continuous pre-training)

* Needs license agreement in advance.

cd /fsx

huggingface-cli login

huggingface-cli download meta-llama/Meta-Llama-3-70B --local-dir Meta-Llama-3-70B

* Prepare initial weight by python Llama3-70B_save.py 
    * for continuous pre-training only


* Use downloaded config and tokenizer files. 

cd ~/examples/tp_pp_llama2_hf_pretrain/
cp /fsx/Meta-Llama-3-70B/config.json ./70B_config/
cp /fsx/Meta-Llama-3-70B/tokenizer* .

* Added 3 parameters at the bottom as below

$ cat ./70B_config/config.json
```
{
  "architectures": [
    "LlamaForCausalLM"
  ],
  "attention_bias": false,
  "attention_dropout": 0.0,
  "bos_token_id": 128000,
  "eos_token_id": 128001,
  "hidden_act": "silu",
  "hidden_size": 8192,
  "initializer_range": 0.02,
  "intermediate_size": 28672,
  "max_position_embeddings": 8192,
  "model_type": "llama",
  "num_attention_heads": 64,
  "num_hidden_layers": 80,
  "num_key_value_heads": 8,
  "pretraining_tp": 1,
  "rms_norm_eps": 1e-05,
  "rope_scaling": null,
  "rope_theta": 500000.0,
  "tie_word_embeddings": false,
  "torch_dtype": "bfloat16",
  "transformers_version": "4.40.0.dev0",
  "use_cache": true,
  "vocab_size": 128256,
  "sequence_parallel_enabled": false,
  "selective_checkpoint_enabled": false,
  "move_model_to_device":false
}
```

cp 70B_config/config.json .

* Add self.rope_theta = config.rope_theta in modeling_llama_nxd.py, at LINE 230

class LlamaAttention(LlamaAttentionHF):
    """Multi-headed attention from 'Attention Is All You Need' paper"""

    def __init__(self, config: LlamaConfig):
        nn.Module.__init__(self)
        self.config = config
        self.hidden_size = config.hidden_size
        self.num_heads = config.num_attention_heads
        self.head_dim = self.hidden_size // self.num_heads
        self.num_key_value_heads = config.num_key_value_heads
        self.num_key_value_groups = self.num_heads // self.num_key_value_heads
        self.pretraining_tp = config.pretraining_tp
        self.max_position_embeddings = config.max_position_embeddings
        self.rope_theta = config.rope_theta

Update library

$ pip list | grep transformers
transformers                  4.31.0
$ pip list | grep tokenizers
tokenizers                    0.13.3

$ pip install -U  transformers tokenizers
Successfully installed tokenizers-0.19.1 transformers-4.40.0

Create dataset

python3 get_dataset.py

Run training job

* Changed library version back to 4.31.0 before running the training job

python3 -m pip install -r requirements.txt

* run compilation

sbatch --exclusive --nodes 512 --cpus-per-task 128  --wrap="srun neuron_parallel_compile bash $(pwd)/run_llama_70b_tp_pp.sh"

* run training job

sbatch --exclusive --nodes 256 run.slurm_test ./run_llama_70b_tp_pp.sh



TPS Results

The result is consistent to Llama2-70B performance test - Performance check: Trn1.32xlarge 512 nodes test record


512 nodes test 

Log Analysis JOB=83 from Apr 20 10:43- Apr 21 12:07 (UTC) for > 24H  : Llama3-70B pre-training.

* slurm-run.slurm_test-83.out / slurm-run.slurm_test-83.out.zip

step 66 step_time 5.986423969268799s throughput 113.87963815345755 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 67 step_time 6.066925048828125s throughput 113.73222099955697 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 68 step_time 5.873164415359497s throughput 114.06498701742004 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 69 step_time 6.072657823562622s throughput 113.82438612782306 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 70 step_time 5.872492551803589s throughput 113.85327030170366 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 71 step_time 5.845523834228516s throughput 112.52164836064796 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan
step 72 step_time 5.971921443939209s throughput 111.64248824174051 seq/s loss nan val-loss: None current_lr: 3.98522e-06 grad norm nan

* Restarted the job because loss was all nan (it seemed I loaded incorrect checkpoint - which was created by pre-compile step - at the beginning).

Log Analysis JOB=84 from Apr 21, 12:14-Apr 24 13:38  (UTC) for > 72H  : Llama3-70B pre-training.

* slurm-run.slurm_test-84.out / slurm-run.slurm_test-84.out.zip

step 28 step_time 5.86236310005188s throughput 112.6864625484136 seq/s loss 12.078991651535034 val-loss: None current_lr: 3.999999999474788e-06 grad norm 21.875
step 29 step_time 6.021969318389893s throughput 113.49026139257543 seq/s loss 11.80674123764038 val-loss: None current_lr: 3.99999999941481e-06 grad norm 17.25
step 30 step_time 5.718714475631714s throughput 113.93113573044499 seq/s loss 11.7701997756958 val-loss: None current_lr: 3.99999999935159e-06 grad norm 11.8125

* Seeing node replacement (at step 18xx)
    * i-07b5f6c3ad7812915 → auto-terminated at Apr 22,  05:10 (UTC)
        * 2024-04-22 05:10:48,491 - [slurm_plugin.instance_manager:delete_instances] - INFO - Terminating instances (x1) ['i-07b5f6c3ad7812915']
            2024-04-22 05:10:51,140 - [slurm_plugin.instance_manager:_update_slurm_node_addrs_and_failed_nodes] - INFO - Nodes are now configured with instances (x1) ["('compute1-st-queue1-i1-462', EC2Instance(id='i-00b3002a5499c23e5', private_ip='10.0.145.160', hostname='ip-10-0-145-160', launch_time=datetime.datetime(2024, 4, 22, 5, 10, 50, tzinfo=tzlocal()), slurm_node=None))"]
            2024-04-22 05:15:48,539 - [slurm_plugin.console_logger:_get_console_output_from_nodes] - INFO - Retrieving Console Output for node i-07b5f6c3ad7812915 (compute1-st-queue1-i1-462)
        * i-00b3002a5499c23e5 → added as replacement. auto-resumed the job
    * auto-resumed from step 1800
* Reboot without node replacement (at step 5090) - auto-resumed at Apr 23 15:42 (UTC)
    * ERROR:torch.distributed.elastic.multiprocessing.api:failed (exitcode: -11) local_rank: 13 (pid: 1940587) of binary: /home/ubuntu/aws_neuron_venv_pytorch/bin/python
        2024-04-23 15:42:02.960584: E tensorflow/core/distributed_runtime/master_session.cc:570] RunStep still blocked after 60 seconds. Failed with error status: CANCELLED: RunManyGraphs
        2024-04-23 15:42:02.960630: E tensorflow/core/distributed_runtime/master_session.cc:575] - No response from RunGraph call to worker: /job:c_localservice/replica:0/task:130
    * 2024-Apr-23 15:45:39.419290python3: /local/p4clients/pkgbuild-lyZDF/workspace/src/KaenaRuntime/kmgr/kmgr_async_exec.cc:27: void kmgr_async_exec_default_exec_status_callback(void*, uint32_t, uint32_t, uint64_t, NRT_STATUS): Assertion `0' failed.
        + exit 1
        srun: error: compute1-st-queue1-i1-131: task 130: Exited with exit code 1
        srun: Terminating StepId=84.0
        slurmstepd: error: *** STEP 84.0 ON compute1-st-queue1-i1-1 CANCELLED AT 2024-04-23T15:45:48 ***
    * auto-resumed from step 5000
* Cancelled JOB=84 to release 512 nodes in Apr 24, 13:38.
    * total >72 hours working - till step 7000

Log Analysis JOB=86 from Apr 24 15:04 - Apr 25 12:25 (UTC) for > 21H  : Llama3-70B pre-training.

* slurm-run.slurm_test-86.out
* 256 node
* Ran HW checker - no issue - all 256 nodes were PASS.
* No HW failures in the training job



Log Analysis JOB=87 from Apr 25 12:58 - xx:xx (UTC) for > xxH  : Llama3-70B pre-training.

* 
* 256 node
* Enabled async checkpoint training
* 




16 nodes test 

    * slurm-68-llama3-16nodes.out

step 50 step_time 126.00786638259888s throughput 7.988989798821986 seq/s loss 10.441542461514473 grad norm 4.21875
step 51 step_time 125.69609355926514s throughput 7.990604678547464 seq/s loss 10.371114950627089 grad norm 4.375
step 52 step_time 125.78513288497925s throughput 7.991405660976181 seq/s loss 10.296276681125164 grad norm 4.125
step 53 step_time 126.00742626190186s throughput 7.993430201244795 seq/s loss 10.200960110872984 grad norm 4.25
step 54 step_time 125.66633415222168s throughput 7.993947284704229 seq/s loss 10.089225608855486 grad norm 4.3125
step 55 step_time 125.59471559524536s throughput 7.995917592590176 seq/s loss 9.997167654335499 grad norm 3.953125
step 56 step_time 125.64142513275146s throughput 7.994964163990468 seq/s loss 9.933526553213596 grad norm 3.71875



Next Step

* To convert the meta’s weight to NxD format and run continuous pre-training from meta’s weight.
* To confirm how to run with 8192 seq_len
    * RICOH reported OOM when tested.



Memo 

* We should set selective checkpoint and sequence parallel on for better performance
* And looking at the scripts, both of those values were set to 1/true by the scripts, so my config.json values of false are being effectively ignored.
* move_model_to_device was a different story, because it is neither a torchrun arg in the run…sh script nor is it an arg being parsed in the run…py script. So that value is being read from the config.json and passed through to the instantiation of the Llama modules.

config.json
  "sequence_parallel_enabled": false,
  "selective_checkpoint_enabled": false,

overridden by

run_llama_70b_tp_pp.sh
    --use_selective_checkpoint 1 \

and 

run_llama_nxd.py
    opt_grp.add_argument("--use_sequence_parallel", default=1, type=int, help="enable sequence parallelism")

because 

run_llama_nxd.py
    config.sequence_parallel_enabled = args.use_sequence_parallel > 0
    config.selective_checkpoint_enabled = args.use_selective_checkpoint > 0

