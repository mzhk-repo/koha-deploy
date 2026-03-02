# CHANGELOG Volume 03 (2026)

Анотація:
- Контекст: продовження hardening CI/CD після завершення основного блоку roadmap 1.1.
- Зміст: тимчасове risk acceptance для Trivy у release-вікні та стабілізація підключення ignore-файлу в image scans.

---

## 2026-03-02

### 1) Тимчасовий ignore-list для Trivy з expiry/risk acceptance

- Додано файл:
  - [.trivyignore.yaml](/home/pinokew/Koha/koha-deploy/.trivyignore.yaml)

- Формат винятків приведено до YAML-шаблону як в `archive/.trivyignore.yaml`:
  - `vulnerabilities[].id`
  - `vulnerabilities[].expired_at`
  - `vulnerabilities[].statement`

- Додані тимчасові винятки з окремим `expired_at` для кожного ID:
  - `CVE-2025-68121`
  - `CVE-2025-58183`
  - `CVE-2025-61726`
  - `CVE-2025-61728`
  - `CVE-2025-61729`
  - `CVE-2025-61730`
  - `CVE-2025-68973`
  - `GHSA-72hv-8253-57qq`

- Важливо:
  - це тимчасовий захід для проходження релізного вікна;
  - після оновлення базових образів винятки мають бути прибрані.

### 2) Фікс: підключення `.trivyignore` у `Trivy image` кроці

- Оновлено workflow:
  - [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml)

- Для `Trivy images` додано:
  - `-v "$PWD:/work"`
  - `-w /work`
  - `--ignorefile /work/.trivyignore.yaml`
  - `--scanners vuln`
  - `--cache-dir /trivy-cache` + mount `-v "${cache_dir}:/trivy-cache"`

- Результат:
  - YAML ignore-файл гарантовано застосовується в контейнері Trivy під час image scan;
  - кеш Trivy повторно використовується між сканами образів у межах job.

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить.

### 3) Централізація версій CI-утиліт у `env` + digest pin для hadolint

- У [ci-cd-checks.yml](/home/pinokew/Koha/koha-deploy/.github/workflows/ci-cd-checks.yml) винесено image refs у top-level `env`:
  - `TRIVY_IMAGE`
  - `HADOLINT_IMAGE`
  - `SHELLCHECK_IMAGE`
  - `GITLEAKS_IMAGE`
  - `SYFT_IMAGE`

- Оновлено кроки на використання змінних з `env`:
  - Shellcheck
  - Gitleaks
  - SBOM (syft)

- `HADOLINT_IMAGE` запінено на digest:
  - `hadolint/hadolint@sha256:84c2f9088a8cb0ea2bd16b5349186770d16441e77eec1a1d1e0574cf7dff47ac`

- Перевірено:
  - `actionlint .github/workflows/ci-cd-checks.yml` проходить.
