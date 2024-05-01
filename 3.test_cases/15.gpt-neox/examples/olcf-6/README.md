
# Pythia GPT-NeoX Test Case <!-- omit in toc -->

This test case illustrates how to train [Pythia](https://arxiv.org/abs/2304.01373) model using GPT-Neox. 

## 1. Preparation

This test case assumes that you have built GPT-NeoX container `../../0.gpt-neox.dockerfile`.

## 2. Download Dataset 

This test case make use of [Tokenized Data for FORGE Foundation Models](https://doi.ccs.ornl.gov/ui/doi/453). Download the data and place as follows:

```bash
/fsx/data/olcf
├── README.txt
├── all_text_document.bin
├── all_text_document.idx
└── all_vocab.json
```

This dataset comprises a vast corpus of 257 billion tokens, accompanied by the corresponding vocabulary file employed in the pre-training of FORGE foundation models. The primary data source for this corpus is scientific documents derived from diverse origins, and they have been tokenized using the Hugging Face BPE tokenizer. Further details about this research can be found in the publication titled "FORGE: Pre-Training Open Foundation Models for Science" authored by Junqi Yin, Sajal Dash, Feiyi Wang, and Mallikarjun (Arjun) Shankar, presented at SC'23. The data tokenization pipeline and resulting artifacts use CORE data [Ref: Knoth, P., & Zdrahal, Z. (2012). CORE: three access levels to underpin open access. D-Lib Magazine, 18(11/12)]. For use of these data sets for any purpose, please follow the guidelines provided in https://core.ac.uk/terms .

## 3. Train 

Now that you can kickstart the training with:

```bash
sbatch 1.train.sbatch
```

