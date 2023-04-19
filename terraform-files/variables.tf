variable "tcp-ports" {
  default = [2377, 7946, 80, 8080, 22]
}

variable "amazon-linux-2" {
  default = "ami-069aabeee6f53e7bf"
}

variable "instance-type" {
  default = "t2.micro"
}

variable "my-key" {
  default = "firstkey"
}