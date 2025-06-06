variable "VPC_IPS" {
  type = list(string)
}

variable "Subnet_VPC1" {
  type = string
}

variable "Subnet_VPC2" {
  type = string
}

variable "Subnet_Private_VPC2" {
  type = string
}

variable "ftp_user" {
  description = "Usuario FTP"
  type = string
}

variable "ftp_password" {
  description = "Contraseña FTP"
  type = string
}

variable "aws_access_key_id"{
  description = "access key amazon"
  type = string
}

variable "aws_secret_access_key"{
  description = "secret amazon"
  type = string
}

variable "aws_session_token" {
  description = "session token"
  type = string
}