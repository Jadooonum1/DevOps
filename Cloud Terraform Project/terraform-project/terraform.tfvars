# --- LocalStack (default for this coursework) ---
localstack_endpoint = "http://localhost:4566"
ami_name_pattern    = "amzn-ami-hvm-*-x86_64-gp2" # LocalStack's mock image catalogue has no AL2023

# --- real AWS: comment the two lines above, and set your own IP ---
# admin_cidr = "198.51.100.23/32"

environment         = "dev"
public_subnet_count = 2
instance_count      = 1
instance_type       = "t3.micro"
