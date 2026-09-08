# Minimal example: the module reads its configuration from
# modules/vpc/vars.yaml, so this instantiation takes no inputs. Edit that file
# to change the network layout used by this example.
module "network" {
  source = "../../modules/vpc"
}
