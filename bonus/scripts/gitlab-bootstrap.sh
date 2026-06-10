#!/bin/bash
set -euo pipefail

GITLAB_NS="${GITLAB_NS:-gitlab}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-RootIot42Bonus!}"

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

root_exists() {
  kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rails runner \
    "exit(User.find_by(username: 'root') ? 0 : 1)" 2>/dev/null
}

ensure_root() {
  kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rails runner "$(cat <<RUBY
pw = '${GITLAB_ROOT_PASSWORD}'
begin
  u = User.find_by(username: 'root')
  unless u
    org = Organizations::Organization.first
    if org.nil?
      org = Organizations::Organization.create!(
        name: 'GitLab',
        path: 'gitlab',
        visibility_level: Gitlab::VisibilityLevel::PUBLIC
      )
    end
    u = User.new(
      name: 'Administrator',
      username: 'root',
      email: 'admin@example.com',
      admin: true,
      confirmed_at: Time.current
    )
    u.password = pw
    u.password_confirmation = pw
    u.save!(validate: false)
    ns = Namespaces::UserNamespace.create!(
      name: 'root',
      path: 'root',
      owner: u,
      organization: org
    )
    u.update!(namespace: ns)
    puts 'created root'
  else
    unless u.namespace
      org = Organizations::Organization.first
      if org
        ns = Namespaces::UserNamespace.find_or_create_by!(path: 'root') do |x|
          x.name = 'root'
          x.owner = u
          x.organization = org
        end
        u.update!(namespace: ns)
      end
    end
    unless u.valid_password?(pw)
      u.password = pw
      u.password_confirmation = pw
      u.save!(validate: false)
    end
    puts 'root ok'
  end
rescue StandardError => e
  puts "ERROR: \#{e.class}: \#{e.message}"
  exit 1
end
RUBY
)" || return 1
}

main() {
  wait_gitlab || {
    echo "GitLab not ready"
    gitlab_diagnose
    exit 1
  }
  ensure_root || {
    gitlab_diagnose
    exit 1
  }
  info "Login: root / ${GITLAB_ROOT_PASSWORD}"
}

main "$@"
