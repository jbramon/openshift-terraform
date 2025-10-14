resource "aws_instance" "web" {
  ami                         = var.amiID[var.region]
  instance_type               = "t2.large"
  key_name                    = "Pair14"
  vpc_security_group_ids      = [aws_security_group.pair14-sg.id]
  availability_zone           = var.zone1
  associate_public_ip_address = true

  user_data = <<-EOF
  #!/bin/bash
  echo "===== Starting EC2 setup for OpenShift deployment =====" >> /var/log/user_data.log

  export OC_CLUSTER_URL="${var.openshift_url}"
  export OC_TOKEN="${var.openshift_token}"
  export GH_PAT="${var.gh_pat}"
  PROJECT="kylecanonigo-dev"

  yum update -y
  yum install -y curl tar gzip sudo jq

  echo "===== Installing OpenShift CLI =====" >> /var/log/user_data.log
  curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o oc.tar.gz
  tar -xzf oc.tar.gz -C /usr/local/bin
  chmod +x /usr/local/bin/oc

  echo "===== Logging in to OpenShift =====" >> /var/log/user_data.log
  oc login "$OC_CLUSTER_URL" --token="$OC_TOKEN" --insecure-skip-tls-verify=true >> /var/log/user_data.log 2>&1

  echo "===== Ensuring project exists =====" >> /var/log/user_data.log
  oc new-project "$PROJECT" || oc project "$PROJECT"

  echo "===== Deploying Jenkins Ephemeral =====" >> /var/log/user_data.log
  if ! oc get dc jenkins -n "$PROJECT" >/dev/null 2>&1; then
    oc new-app jenkins-ephemeral -n "$PROJECT" >> /var/log/user_data.log 2>&1
  else
    echo "Jenkins already exists in $PROJECT" >> /var/log/user_data.log
  fi

  oc rollout status dc/jenkins -n "$PROJECT" --timeout=300s >> /var/log/user_data.log 2>&1

  echo "===== Creating Jenkins pipeline BuildConfig =====" >> /var/log/user_data.log
  cat <<YAML | oc apply -f - -n "$PROJECT"
  apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: ci-cd
    labels:
      app: ci-cd
  spec:
    source:
      type: Git
      git:
        uri: "https://github.com/jbramon/kylecanonigo-project.git"
        ref: main
    strategy:
      type: JenkinsPipeline
      jenkinsPipelineStrategy:
        jenkinsfilePath: Jenkinsfile
    triggers:
      - type: ConfigChange
      - type: ImageChange
  YAML

  echo "===== Creating GitHub Credentials Secret =====" >> /var/log/user_data.log
  oc delete secret github-credentials --ignore-not-found -n "$PROJECT"
  oc create secret generic github-credentials \
    --from-literal=username="jbramon" \
    --from-literal=password="$${GH_PAT}" \
    -n "$PROJECT"

  echo "===== Linking GitHub Secret to BuildConfig =====" >> /var/log/user_data.log
  oc set build-secret --source bc/ci-cd github-credentials -n "$PROJECT"

  echo "===== Removing old webhooks from sample-app-jenkins-new =====" >> /var/log/user_data.log
  if oc get bc sample-app-jenkins-new -n "$PROJECT" >/dev/null 2>&1; then
    for i in {1..5}; do
      echo "Attempt $i to delete triggers..." >> /var/log/user_data.log
      oc patch bc sample-app-jenkins-new -n "$PROJECT" --type=json -p='[{"op": "remove", "path": "/spec/triggers"}]' >> /var/log/user_data.log 2>&1 || true
      sleep 5
      TRIGGERS=$(oc get bc sample-app-jenkins-new -n "$PROJECT" -o jsonpath='{.spec.triggers}' 2>/dev/null)
      if [[ -z "$TRIGGERS" || "$TRIGGERS" == "[]" ]]; then
        echo "✅ All webhooks removed successfully." >> /var/log/user_data.log
        break
      fi
      if [[ "$i" -eq 5 ]]; then
        echo "❌ Failed to remove webhooks after 5 attempts." >> /var/log/user_data.log
      fi
    done
  else
    echo "⚠️ sample-app-jenkins-new BuildConfig not found — skipping removal." >> /var/log/user_data.log
  fi

  echo "===== Adding GitHub & Generic webhooks to ci-cd =====" >> /var/log/user_data.log
  oc patch bc ci-cd -n "$PROJECT" --type=merge -p '{
    "spec": {
      "triggers": [
        {
          "type": "GitHub",
          "github": {
            "secret": "my-github-secret"
          }
        },
        {
          "type": "Generic",
          "generic": {
            "secret": "my-generic-secret"
          }
        }
      ]
    }
  }' >> /var/log/user_data.log 2>&1

  echo "===== Starting Jenkins pipeline build =====" >> /var/log/user_data.log
  oc start-build ci-cd -n "$PROJECT" >> /var/log/user_data.log 2>&1 || echo "⚠️ Build failed or already exists." >> /var/log/user_data.log

  echo "===== Waiting for build to complete =====" >> /var/log/user_data.log
  sleep 120

  echo "===== Creating Deployment and Route =====" >> /var/log/user_data.log
  cat <<YAML | oc apply -f - -n "$PROJECT"
  apiVersion: apps.openshift.io/v1
  kind: DeploymentConfig
  metadata:
    name: webapp
    labels:
      app: webapp
  spec:
    replicas: 1
    selector:
      app: webapp
    template:
      metadata:
        labels:
          app: webapp
      spec:
        containers:
        - name: webapp
          image: image-registry.openshift-image-registry.svc:5000/$PROJECT/ci-cd:latest
          ports:
          - containerPort: 8080
          imagePullPolicy: Always
  ---
  apiVersion: v1
  kind: Service
  metadata:
    name: webapp
    labels:
      app: webapp
  spec:
    ports:
      - port: 8080
        targetPort: 8080
    selector:
      app: webapp
  ---
  apiVersion: route.openshift.io/v1
  kind: Route
  metadata:
    name: webapp
    labels:
      app: webapp
  spec:
    to:
      kind: Service
      name: webapp
    port:
      targetPort: 8080
    tls:
      termination: edge
  YAML

  echo "===== ✅ Deployment complete with GitHub authentication =====" >> /var/log/user_data.log
EOF

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name    = "openshift-terraform"
    Project = "Pair14"
  }
}

resource "aws_ec2_instance_state" "web-state" {
  instance_id = aws_instance.web.id
  state       = "running"
}

output "WebPublicIP" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "WebPrivateIP" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.web.private_ip
}

