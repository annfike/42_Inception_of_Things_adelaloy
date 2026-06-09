# Documentation index

```
docs/
├── README.md                 ← you are here
├── setup/                    # VM and defense environment
│   ├── vm-setup.md           # MacBook + UTM (p3, bonus)
│   ├── school-defense.md     # School Linux + VirtualBox (all parts)
│   └── p1-nested-virt.md     # p1/p2 inside a Linux VM (nested virt)
├── p1/
│   ├── checklist.md          # Setup + verification
│   └── config-guide.md       # File-by-file explanation
├── p2/
│   ├── checklist.md
│   └── config-guide.md
├── p3/
│   ├── checklist.md
│   └── config-guide.md
└── bonus/
    ├── checklist.md
    └── config-guide.md
```

## By part

| Part | Checklist | Config guide | Code |
|------|-----------|--------------|------|
| **p1** | [checklist](p1/checklist.md) | [config-guide](p1/config-guide.md) | `p1/` |
| **p2** | [checklist](p2/checklist.md) | [config-guide](p2/config-guide.md) | `p2/` |
| **p3** | [checklist](p3/checklist.md) | [config-guide](p3/config-guide.md) | `p3/`, [README](../p3/README.md) |
| **bonus** | [checklist](bonus/checklist.md) | [config-guide](bonus/config-guide.md) | `bonus/`, [README](../bonus/README.md) |

## Environment setup

| Doc | When to use |
|-----|-------------|
| [setup/school-defense.md](setup/school-defense.md) | Intel school PC, VirtualBox, nested VM |
| [setup/vm-setup.md](setup/vm-setup.md) | MacBook + UTM for p3/bonus |
| [setup/p1-nested-virt.md](setup/p1-nested-virt.md) | p1/p2 Vagrant inside Linux VM (KVM/libvirt) |

## Quick defense order

1. p1 → destroy → p2 → destroy → p3 → bonus (one module at a time on limited RAM)
