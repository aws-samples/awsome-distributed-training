import os
import sys
import json

import numpy as np
import tensorflow as tf

"""Tensorflow distributed training example
This code is retrived from https://www.tensorflow.org/tutorials/distribute/multi_worker_with_keras
"""

def mnist_dataset(batch_size):
  (x_train, y_train), _ = tf.keras.datasets.mnist.load_data()
  # The `x` arrays are in uint8 and have values in the [0, 255] range.
  # You need to convert them to float32 with values in the [0, 1] range.
  x_train = x_train / np.float32(255)
  y_train = y_train.astype(np.int64)
  train_dataset = tf.data.Dataset.from_tensor_slices(
      (x_train, y_train)).shuffle(60000).repeat().batch(batch_size)
  return train_dataset

def build_and_compile_cnn_model():
  model = tf.keras.Sequential([
      tf.keras.layers.InputLayer(input_shape=(28, 28)),
      tf.keras.layers.Reshape(target_shape=(28, 28, 1)),
      tf.keras.layers.Conv2D(32, 3, activation='relu'),
      tf.keras.layers.Flatten(),
      tf.keras.layers.Dense(128, activation='relu'),
      tf.keras.layers.Dense(10)
  ])
  model.compile(
      loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
      optimizer=tf.keras.optimizers.SGD(learning_rate=0.001),
      metrics=['accuracy'])
  return model

def main():
    per_worker_batch_size = 64
    tf_config = json.loads(os.environ['TF_CONFIG'])
    num_workers = len(tf_config['cluster']['worker'])

    strategy = tf.distribute.MultiWorkerMirroredStrategy()

    global_batch_size = per_worker_batch_size * num_workers
    multi_worker_dataset = mnist_dataset(global_batch_size)

    with strategy.scope():
        # Model building/compiling need to be within `strategy.scope()`.
        multi_worker_model = build_and_compile_cnn_model()


    multi_worker_model.fit(multi_worker_dataset, epochs=3, steps_per_epoch=70)

if __name__ == "__main__":
    worker_rank = sys.argv[1]
    workers = [*map(lambda x: f"{x}:12345", sys.argv[2:])]
    os.environ["TF_CONFIG"] = json.dumps({
    'cluster': {
        'worker': workers
    },
    'task': {'type': 'worker', 'index': worker_rank}
    })

    print("Hello from Python")
    print(workers, worker_rank)
    print(os.environ["TF_CONFIG"])
    main()