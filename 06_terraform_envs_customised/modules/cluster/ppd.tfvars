# Pre-Prod cluster for dev, e2e, prf namespaces
cluster_env                 = "ppd"
domain                      = "d1matrix.com"
aws_region                  = "sa-east-1"
external_dns_domain_filters = ["d1matrix.com"]
namespaces_app              = ["marcellodesales-hellok8s-sae1-ppd-dev", "marcellodesales-hellok8s-sae1-ppd-qal"]
namespaces_system           = ["cert-manager"]
# https://medium.com/@swazza85/dealing-with-pod-density-limitations-on-eks-worker-nodes-137a12c8b218
# Total Pods per instance_type: https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt
instance_types      = ["t3.micro"]
k8s_version         = 1.18
k8s_min_capacity    = 5
k8s_max_capacity    = 10
k8s_manage_aws_auth = false
