import subprocess

def destroy_indra():
    terraform_dir = "terraform/"

    command = [
        "terraform", "destroy",
        "-auto-approve"
    ]

    try:
        result = subprocess.run(command, cwd=terraform_dir, text=True, capture_output=True, check=True)
        print("Destroy completado con éxito.")
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print("Error durante el destroy:")
        print(e.stderr)

if __name__ == "__main__":
    destroy_indra()
