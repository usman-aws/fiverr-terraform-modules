# Example: Basic VPC

Instantiates the [`vpc`](../../modules/vpc) module as an external caller
would, to prove it composes correctly outside its own directory. The network
layout itself comes from [`modules/vpc/vars.yaml`](../../modules/vpc/vars.yaml).

```bash
terraform init
terraform plan
terraform apply
```

Region is fixed to `us-east-1` in `providers.tf`; change it there if you plan
to `apply` this example (and keep `vars.yaml`'s `region` key in sync, since
it's used to build VPC endpoint service names).
