from mingpt.utils import CfgNode as CN

class TrainConfig:
    @staticmethod
    def get_default_config():
        C = CN()
        # device to train on
        C.device = 'auto'
        # dataloder parameters
        C.num_workers = 0
        # optimizer parameters
        C.batch_size = 8
        C.learning_rate = 3e-4
        C.betas = (0.9, 0.95)
        C.max_iters = 8000
        C.weight_decay = 0.1 # only applied on matmul weights
        C.grad_norm_clip = 1.0
        return C
