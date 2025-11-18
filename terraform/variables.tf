variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "The path to the public SSH key."
  type        = string
}

variable "private_key_path" {
  description = "The path to the private SSH key."
  type        = string
}
