from python_terraform import Terraform

def creacion_de_vpc():
    tf = Terraform(working_dir="terraform/")
    tf.init(capture_output=False)
    tf.apply(capture_output=False, skip_plan=True, auto_approve=True)

if __name__ == "__main__":
    creacion_de_vpc()
