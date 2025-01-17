#!/usr/bin/env bats

load "${BATS_PLUGIN_PATH}/load.bash"

# Uncomment to enable stub debug output:
# export AWS_STUB_DEBUG=/dev/tty

setup() {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_CLUSTER=my-cluster
  export BUILDKITE_PLUGIN_ECS_DEPLOY_SERVICE=my-service
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TASK_FAMILY=hello-world
  export BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE=hello-world:llamas
}

@test "Run a deploy when service exists" {

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo '1'" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with multiple images" {
  unset BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE
  export BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE_0=hello-world:llamas
  export BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE_1=hello-world:alpacas

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task-multiple.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo '1'" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Add env vars on multiple images" {
  unset BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE
  export BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE_0=hello-world:llamas
  export BUILDKITE_PLUGIN_ECS_DEPLOY_IMAGE_1=hello-world:alpacas
  export BUILDKITE_PLUGIN_ECS_DEPLOY_ENV_0="FOO=bar"
  export BUILDKITE_PLUGIN_ECS_DEPLOY_ENV_1="BAZ=bing"

  # first command stubbed saves the container definition to ${TMP_DIR}/container_definition for later review and manipulation
  # we should be stubbing a lot more calls, but we don't care about those so let the stubbing fail
  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task-multiple.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo \"\$6\" > ${_TMP_DIR}/container_definition ; echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo '1'" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success

  # check that the definition was updated accordingly
  assert_equal "$(jq -r '.[0].environment[0].name'  "${_TMP_DIR}"/container_definition)" 'FOO'
  assert_equal "$(jq -r '.[0].environment[0].value' "${_TMP_DIR}"/container_definition)" 'bar'
  assert_equal "$(jq -r '.[1].environment[0].name'  "${_TMP_DIR}"/container_definition)" 'FOO'
  assert_equal "$(jq -r '.[1].environment[0].value' "${_TMP_DIR}"/container_definition)" 'bar'
  assert_equal "$(jq -r '.[0].environment[1].name'  "${_TMP_DIR}"/container_definition)" 'BAZ'
  assert_equal "$(jq -r '.[0].environment[1].value' "${_TMP_DIR}"/container_definition)" 'bing'
  assert_equal "$(jq -r '.[1].environment[1].name'  "${_TMP_DIR}"/container_definition)" 'BAZ'
  assert_equal "$(jq -r '.[1].environment[1].value' "${_TMP_DIR}"/container_definition)" 'bing'

  unstub aws
}

@test "Run a deploy when service does not exist" {
  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo -n ''" \
    "ecs create-service --cluster my-cluster --service-name my-service --task-definition hello-world:1 --desired-count 1 --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 --cli-input-json '{}' : echo -n ''" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with a new service with definition" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_SERVICE_DEFINITION=examples/service-definition.json

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo -n ''" \
    "ecs create-service --cluster my-cluster --service-name my-service --task-definition hello-world:1 --desired-count 1 --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 --cli-input-json \* : echo -n ''" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with task role" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TASK_ROLE_ARN=arn:aws:iam::012345678910:role/world

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* --task-role-arn arn:aws:iam::012345678910:role/world : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo '1'" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with target group" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TARGET_GROUP=arn:aws:elasticloadbalancing:us-east-1:012345678910:targetgroup/alb/e987e1234cd12abc
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TARGET_CONTAINER_NAME=nginx
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TARGET_CONTAINER_PORT=80

  alb_config='[{"loadBalancers":[{"containerName":"nginx","containerPort":80,"targetGroupArn":"arn:aws:elasticloadbalancing:us-east-1:012345678910:targetgroup/alb/e987e1234cd12abc"}]}]'

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo -n ''" \
    "ecs create-service --cluster my-cluster --service-name my-service --task-definition hello-world:1 --desired-count 1 --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:us-east-1:012345678910:targetgroup/alb/e987e1234cd12abc,containerName=nginx,containerPort=80 --cli-input-json '{}' : echo -n ''" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo '$alb_config'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with ELBv1" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_LOAD_BALANCER_NAME=nginx-elb
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TARGET_CONTAINER_NAME=nginx
  export BUILDKITE_PLUGIN_ECS_DEPLOY_TARGET_CONTAINER_PORT=80

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo -n ''" \
    "ecs create-service --cluster my-cluster --service-name my-service --task-definition hello-world:1 --desired-count 1 --deployment-configuration maximumPercent=200,minimumHealthyPercent=100 --load-balancers loadBalancerName=nginx-elb,containerName=nginx,containerPort=80 --cli-input-json '{}' : echo -n ''" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo '[{\"loadBalancers\":[{\"loadBalancerName\": \"nginx-elb\",\"containerName\": \"nginx\",\"containerPort\": 80}]}]'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy with execution role" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_EXECUTION_ROLE=arn:aws:iam::012345678910:role/world

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* --execution-role-arn arn:aws:iam::012345678910:role/world : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo '1'" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Create a service with deployment configuration" {
  export BUILDKITE_PLUGIN_ECS_DEPLOY_DEPLOYMENT_CONFIGURATION="0/100"

  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : cat examples/described-task.json" \
    "ecs register-task-definition --family hello-world --container-definitions \* : echo '{\"taskDefinition\":{\"revision\":1}}'" \
    "ecs describe-services --cluster my-cluster --service my-service --query \"services[?status=='ACTIVE'].status\" --output text : echo -n ''" \
    "ecs create-service --cluster my-cluster --service-name my-service --task-definition hello-world:1 --desired-count 1 --deployment-configuration maximumPercent=100,minimumHealthyPercent=0 --cli-input-json '{}' : echo -n ''" \
    "ecs describe-services --cluster my-cluster --services my-service --query \"services[?status=='ACTIVE']\" : echo 'null'" \
    "ecs update-service --cluster my-cluster --service my-service --task-definition hello-world:1 : echo ok" \
    "ecs wait services-stable --cluster my-cluster --services my-service : echo ok" \
    "ecs describe-services --cluster my-cluster --service my-service --query 'services[].events' --output text : echo ok"

  run "$PWD/hooks/command"

  assert_success
  assert_output --partial "Service is up 🚀"

  unstub aws
}

@test "Run a deploy when the container definition is incorrect" {
  
  stub aws \
    "ecs describe-task-definition --task-definition hello-world --query taskDefinition : echo '{}'"

  run "$PWD/hooks/command"
  
  assert_failure
  assert_output --partial 'Invalid container definition (should be in the format of [{"image": "..."}] )'
  
  unstub aws
}

@test "Fail with missing container definition and aws failure" {
  stub aws 'exit 1' # whatever we receive, fail

  run "$PWD/hooks/command"

  assert_failure
  assert_output --partial "Could not obtain existing task definition"

  unstub aws
}
