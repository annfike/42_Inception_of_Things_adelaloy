#!/bin/bash
set -euo pipefail

GITLAB_NS="${GITLAB_NS:-gitlab}"

info() { echo ">>> $1"; }
warn() { echo ">>> $1"; }

gitlab_diagnose() {
  warn "GitLab status:"
  kubectl get pods -n "$GITLAB_NS" -l app=gitlab -o wide 2>/dev/null || true
  kubectl describe pod -n "$GITLAB_NS" -l app=gitlab 2>/dev/null | tail -30 || true
  kubectl logs -n "$GITLAB_NS" deployment/gitlab --tail=40 2>/dev/null || true
}

wait_gitlab() {
  info "Waiting for GitLab (health + rake; often 10-20 min after pod starts)..."
  local i=0
  while [ "$i" -lt 180 ]; do
    local phase ready
    phase=$(kubectl get pods -n "$GITLAB_NS" -l app=gitlab -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
    ready=$(kubectl get pods -n "$GITLAB_NS" -l app=gitlab -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$phase" = "Running" ] && [ "$ready" = "True" ]; then
      if kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rake db:migrate:status >/dev/null 2>&1; then
        info "GitLab is ready."
        return 0
      fi
    fi
    i=$((i + 1))
    if [ $((i % 6)) -eq 0 ]; then
      info "Still waiting... (${i}/180, ~$((i * 10 / 60)) min) phase=${phase:-?} ready=${ready:-?}"
    fi
    sleep 10
  done
  return 1
}

seed_if_empty() {
  local count
  count=$(kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rails runner 'puts User.count' 2>/dev/null | tail -1)
  if [ "$count" = "0" ]; then
    info "Seeding database..."
    kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rake db:seed
  fi
}

fix_root() {
  kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rails runner "$(cat <<'RUBY'
u = User.find_by(username: 'root')
exit 1 unless u
o = Organizations::Organization.first
unless u.namespace
  n = Namespaces::UserNamespace.find_or_create_by!(path: 'root') do |x|
    x.name = 'root'
    x.owner = u
    x.organization = o
  end
  u.update!(namespace: n)
end
unless u.valid_password?('password123')
  u.password = 'password123'
  u.password_confirmation = 'password123'
  u.save(validate: false)
end
puts 'root ok'
RUBY
)"
}

main() {
  wait_gitlab || {
    echo "GitLab not ready"
    gitlab_diagnose
    exit 1
  }
  seed_if_empty
  fix_root
  info "Login: root / password123"
}

main "$@"
