#!/bin/bash
set -euo pipefail

GITLAB_NS="${GITLAB_NS:-gitlab}"

info() { echo ">>> $1"; }

wait_gitlab() {
  info "Waiting for GitLab pod..."
  for _ in $(seq 1 120); do
    if kubectl get pods -n "$GITLAB_NS" -l app=gitlab -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
      if kubectl exec -n "$GITLAB_NS" deployment/gitlab -- gitlab-rake db:migrate:status >/dev/null 2>&1; then
        return 0
      fi
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
  wait_gitlab || { echo "GitLab not ready"; exit 1; }
  seed_if_empty
  fix_root
  info "Login: root / password123"
}

main "$@"
