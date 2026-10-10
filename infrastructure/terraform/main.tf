resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name      = "monitoring"
  namespace = kubernetes_namespace.monitoring.metadata[0].name

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  timeout    = 900

  values = [
    file("${path.module}/helm/monitoring-values.yaml")
  ]

  # Giữ mật khẩu Grafana ở dạng sensitive
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  depends_on = [
    kubernetes_namespace.monitoring
  ]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# Đọc hai Application YAML từ Git repository.
locals {
  argocd_apps = {
    ann_mnist = yamldecode(
      file("${path.module}/../../argocd/application.yaml")
    )

    ann_mnist_monitoring = yamldecode(
      file("${path.module}/../../argocd/application-monitoring.yaml")
    )
  }
}

# Quản lý các Application thông qua chart argocd-apps.
# Tránh dùng kubernetes_manifest vì CRD Application cần tồn tại
# trong cluster trước khi Terraform thực hiện plan.
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"

  values = [
    yamlencode({
      applications = {
        for app_key, app in local.argocd_apps :
        app.metadata.name => {
          namespace   = app.metadata.namespace
          project     = app.spec.project
          source      = app.spec.source
          destination = app.spec.destination
          syncPolicy  = app.spec.syncPolicy
        }
      }
    })
  ]

  depends_on = [
    helm_release.argocd
  ]
}