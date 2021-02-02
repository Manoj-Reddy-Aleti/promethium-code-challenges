module "vpc-test1" {
  source = "terraform-aws-modules/vpc/aws"
  version = "2.68.0"

  name = "promethium-vpc"

  cidr = "10.100.0.0/16"

  azs             = ["us-west-1a"]
  private_subnets = ["10.100.2.0/24"]
  public_subnets  = ["10.100.1.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform       = "true"
  }
}


module "ec2_cluster" {
  source                 = "terraform-aws-modules/ec2-instance/aws"
  version                = "~> 2.0"

  name                   = "promethium-public-instance"
  instance_count         = 1

  ami                    = "ami-06fcc1f0bc2c8943f"
  instance_type          = "t2.micro"
  #key_name               = "Mac"
  #monitoring             = true
  #vpc_security_group_ids = aws_vpc.this
  subnet_id              = join(",",module.vpc-test1.private_subnets)

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}


locals {
  lambda_zip_location = "outputs/status.zip"
}

data "archive_file" "status" {
  type        = "zip"
  source_file = "status.py"
  output_path = local.lambda_zip_location
}

variable "lambda_function_name" {
  default = "promethium_lambda_function"
}

resource "aws_lambda_function" "promethium_lambda" {
  function_name = var.lambda_function_name
  filename = local.lambda_zip_location
  handler = "status.lambda_handler"
  role = aws_iam_role.iam_for_lambda.arn
  runtime = "python3.8"

  environment {
    variables = {
      prv_ip = module.ec2_cluster.private_ip[0]
    }
  }
  source_code_hash = filebase64sha256(local.lambda_zip_location)

  vpc_config {
    subnet_ids = flatten([module.vpc-test1.private_subnets])
    security_group_ids = flatten([module.vpc-test1.default_security_group_id])
  }


  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.example,
  ]
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14


}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy = file("iam/lambda_logging_policy.json")
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

/*
resource "aws_iam_policy" "ec2_network_interface" {
  name        = "ec2_network_interface"
  #path        = "/"
  description = "IAM policy for ec2_network_interface from a lambda"
  policy = file("iam/lambda_ec2_network_interface.json")
}

resource "aws_iam_role_policy_attachment" "ec2_network_int" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.ec2_network_interface.arn
}
*/

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = file("iam/lambda_assume_role.json")
}


resource "aws_cloudwatch_event_rule" "every_one_minute" {
  name                = "every-one-minute"
  description         = "Fires every one minutes"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "check_foo_every_one_minute" {
  rule      = aws_cloudwatch_event_rule.every_one_minute.name
  target_id = "lambda"
  arn       = aws_lambda_function.promethium_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_foo" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promethium_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_one_minute.arn
}