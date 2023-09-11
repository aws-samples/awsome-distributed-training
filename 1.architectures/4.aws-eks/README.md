
# Welcome to your CDK Python project!
This is a project for CDK development with Python.
The `cdk.json` file tells the CDK Toolkit how to execute your app.

# Prerequisites
1. AWS CLI
2. Python 3.8
3. npm
4. npm install -g aws-cdk

# Project

This project is set up like a standard Python project.  The initialization
process also creates a virtualenv within this project, stored under the `.venv`
directory.  To create the virtualenv it assumes that there is a `python3`
(or `python` for Windows) executable in your path with access to the `venv`
package. If for any reason the automatic creation of the virtualenv fails,
you can create the virtualenv manually.

To manually create a virtualenv on MacOS and Linux:

```
$ python3 -m venv .venv
```

After the init process completes and the virtualenv is created, you can use the following
step to activate your virtualenv.

```
$ source .venv/bin/activate
```

If you are a Windows platform, you would activate the virtualenv like this:

```
% .venv\Scripts\activate.bat
```

Once the virtualenv is activated, you can install the required dependencies.

```
$ python -m pip install --upgrade pip
```

```
$ pip install -r requirements.txt
```

At this point you can now synthesize the CloudFormation template for this code.

```
$ cdk synth
```

To add additional dependencies, for example other CDK libraries, just add
them to your `setup.py` file and rerun the `pip install -r requirements.txt`
command.

## Useful commands

 * `cdk ls`          list all stacks in the app
 * `cdk synth`       emits the synthesized CloudFormation template
 * `cdk deploy`      deploy this stack to your default AWS account/region
 * `cdk diff`        compare deployed stack with current state
 * `cdk docs`        open CDK documentation

# References

* [CDK v2 Documentation](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
* [Getting started with CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html)
* [CDK examples](https://github.com/aws-samples/aws-cdk-examples/tree/master/typescript/eks/cluster)
* [CDK API reference](https://docs.aws.amazon.com/cdk/v2/guide/reference.html)
* [CDK API reference EKS quick start](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_eks-readme.html#quick-start)
* [CDK Python API for EKS](https://docs.aws.amazon.com/cdk/api/v2/python/aws_cdk.aws_eks/Cluster.html)
* [CDK for Kubernetes (cdk8s)](https://cdk8s.io/)

