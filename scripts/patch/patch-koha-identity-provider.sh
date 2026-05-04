#!/usr/bin/env bash
# Script Purpose: Manage Koha Identity Provider (OIDC/OAuth) config from env (IaC).
# Usage: ./scripts/patch/patch-koha-identity-provider.sh [--env-file FILE] [--discover] [--apply] [--verify] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/_patch_common.sh"

DO_DISCOVER=true
DO_APPLY=true
DO_VERIFY=true
FLAGS_SEEN=false

usage() {
  cat <<'USAGE'
Usage: ./scripts/patch/patch-koha-identity-provider.sh [options]

Options:
  --env-file FILE     Path to env file (default: ./.env)
  --discover          Print current identity provider + domain config
  --apply             Apply provider/domain config from env
  --verify            Verify DB values match env
  --dry-run           Print actions only
  --help              Show help

Selection behavior:
  By default script runs discover + apply + verify.
  If at least one of --discover/--apply/--verify is explicitly provided,
  only selected actions are executed.

Env model (required unless noted):
  KOHA_IDP_CODE
  KOHA_IDP_DESCRIPTION
  KOHA_IDP_PROTOCOL                 (OIDC/OAuth/LDAP/CAS)
  KOHA_IDP_MATCHPOINT               (email/userid/cardnumber)
  KOHA_IDP_ICON_URL                 (optional)
  KOHA_IDP_CONFIG_KEY
  KOHA_IDP_CONFIG_SECRET
  KOHA_IDP_CONFIG_WELL_KNOWN_URL
  KOHA_IDP_CONFIG_SCOPE             (optional)
  KOHA_IDP_MAPPING_USERID
  KOHA_IDP_MAPPING_EMAIL
  KOHA_IDP_MAPPING_FIRSTNAME
  KOHA_IDP_MAPPING_SURNAME
  KOHA_IDP_DOMAIN                   (use * for all domains)
  KOHA_IDP_UPDATE_ON_AUTH           (0/1)
  KOHA_IDP_DEFAULT_LIBRARY_ID       (optional)
  KOHA_IDP_DEFAULT_CATEGORY_ID      (optional)
  KOHA_IDP_ALLOW_OPAC               (0/1)
  KOHA_IDP_ALLOW_STAFF              (0/1)
  KOHA_IDP_AUTO_REGISTER_OPAC       (0/1)
  KOHA_IDP_AUTO_REGISTER_STAFF      (0/1)

Optional Google cleanup:
  KOHA_DISABLE_GOOGLE_OIDC=true     (default: true)
USAGE
}

parse_args() {
  local rest=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --discover|--apply|--verify)
        if ! ${FLAGS_SEEN}; then
          DO_DISCOVER=false
          DO_APPLY=false
          DO_VERIFY=false
          FLAGS_SEEN=true
        fi
        case "$1" in
          --discover) DO_DISCOVER=true ;;
          --apply) DO_APPLY=true ;;
          --verify) DO_VERIFY=true ;;
        esac
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        rest+=("$1")
        ;;
    esac
    shift
  done

  if ! parse_common_args "${rest[@]}"; then
    usage
    exit 0
  fi
}

sql_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\'/\'\'}"
  printf '%s' "${v}"
}

require_bool01() {
  local key="$1"
  local value="$2"
  [[ "${value}" =~ ^[01]$ ]] || die "${key} must be 0 or 1"
}

load_required_env() {
  KOHA_IDP_CODE="${KOHA_IDP_CODE:-}"
  KOHA_IDP_DESCRIPTION="${KOHA_IDP_DESCRIPTION:-}"
  KOHA_IDP_PROTOCOL="${KOHA_IDP_PROTOCOL:-OIDC}"
  KOHA_IDP_MATCHPOINT="${KOHA_IDP_MATCHPOINT:-userid}"
  KOHA_IDP_ICON_URL="${KOHA_IDP_ICON_URL:-}"

  KOHA_IDP_CONFIG_KEY="${KOHA_IDP_CONFIG_KEY:-}"
  KOHA_IDP_CONFIG_SECRET="${KOHA_IDP_CONFIG_SECRET:-}"
  KOHA_IDP_CONFIG_WELL_KNOWN_URL="${KOHA_IDP_CONFIG_WELL_KNOWN_URL:-}"
  KOHA_IDP_CONFIG_SCOPE="${KOHA_IDP_CONFIG_SCOPE:-openid email}"

  KOHA_IDP_MAPPING_USERID="${KOHA_IDP_MAPPING_USERID:-email}"
  KOHA_IDP_MAPPING_EMAIL="${KOHA_IDP_MAPPING_EMAIL:-email}"
  KOHA_IDP_MAPPING_FIRSTNAME="${KOHA_IDP_MAPPING_FIRSTNAME:-given_name}"
  KOHA_IDP_MAPPING_SURNAME="${KOHA_IDP_MAPPING_SURNAME:-family_name}"

  KOHA_IDP_DOMAIN="${KOHA_IDP_DOMAIN:-*}"
  KOHA_IDP_UPDATE_ON_AUTH="${KOHA_IDP_UPDATE_ON_AUTH:-1}"
  KOHA_IDP_DEFAULT_LIBRARY_ID="${KOHA_IDP_DEFAULT_LIBRARY_ID:-}"
  KOHA_IDP_DEFAULT_CATEGORY_ID="${KOHA_IDP_DEFAULT_CATEGORY_ID:-}"
  KOHA_IDP_ALLOW_OPAC="${KOHA_IDP_ALLOW_OPAC:-1}"
  KOHA_IDP_ALLOW_STAFF="${KOHA_IDP_ALLOW_STAFF:-1}"
  KOHA_IDP_AUTO_REGISTER_OPAC="${KOHA_IDP_AUTO_REGISTER_OPAC:-1}"
  KOHA_IDP_AUTO_REGISTER_STAFF="${KOHA_IDP_AUTO_REGISTER_STAFF:-0}"

  KOHA_DISABLE_GOOGLE_OIDC="${KOHA_DISABLE_GOOGLE_OIDC:-true}"

  [ -n "${KOHA_IDP_CODE}" ] || die "KOHA_IDP_CODE is required"
  [ -n "${KOHA_IDP_DESCRIPTION}" ] || die "KOHA_IDP_DESCRIPTION is required"
  [ -n "${KOHA_IDP_CONFIG_KEY}" ] || die "KOHA_IDP_CONFIG_KEY is required"
  [ -n "${KOHA_IDP_CONFIG_SECRET}" ] || die "KOHA_IDP_CONFIG_SECRET is required"
  [ -n "${KOHA_IDP_CONFIG_WELL_KNOWN_URL}" ] || die "KOHA_IDP_CONFIG_WELL_KNOWN_URL is required"

  case "${KOHA_IDP_PROTOCOL}" in
    OIDC|OAuth|LDAP|CAS) ;;
    *) die "KOHA_IDP_PROTOCOL must be OIDC, OAuth, LDAP, or CAS" ;;
  esac

  case "${KOHA_IDP_MATCHPOINT}" in
    email|userid|cardnumber) ;;
    *) die "KOHA_IDP_MATCHPOINT must be email, userid, or cardnumber" ;;
  esac

  require_bool01 KOHA_IDP_UPDATE_ON_AUTH "${KOHA_IDP_UPDATE_ON_AUTH}"
  require_bool01 KOHA_IDP_ALLOW_OPAC "${KOHA_IDP_ALLOW_OPAC}"
  require_bool01 KOHA_IDP_ALLOW_STAFF "${KOHA_IDP_ALLOW_STAFF}"
  require_bool01 KOHA_IDP_AUTO_REGISTER_OPAC "${KOHA_IDP_AUTO_REGISTER_OPAC}"
  require_bool01 KOHA_IDP_AUTO_REGISTER_STAFF "${KOHA_IDP_AUTO_REGISTER_STAFF}"
}

db_query() {
  local sql="$1"
  docker_runtime_exec db mariadb -N -B -uroot "-p${DB_ROOT_PASS}" -D "${DB_NAME}" -e "${sql}"
}

normalize_fk_value_for_identity_provider_domain() {
  local env_key="$1"
  local fk_column="$2"
  local raw_value="$3"
  local escaped_value ref_table ref_column exists_sql exists

  [ -n "${raw_value}" ] || {
    printf ''
    return 0
  }

  escaped_value="$(sql_escape "${raw_value}")"

  ref_table="$(db_query "SELECT IFNULL(REFERENCED_TABLE_NAME,'') FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='identity_provider_domains' AND COLUMN_NAME='${fk_column}' LIMIT 1;")"
  ref_column="$(db_query "SELECT IFNULL(REFERENCED_COLUMN_NAME,'') FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='identity_provider_domains' AND COLUMN_NAME='${fk_column}' LIMIT 1;")"

  if [ -z "${ref_table}" ] || [ -z "${ref_column}" ]; then
    warn "${env_key}: FK metadata for identity_provider_domains.${fk_column} not found; applying value '${raw_value}' without pre-validation"
    printf '%s' "${escaped_value}"
    return 0
  fi

  exists_sql="SELECT COUNT(*) FROM \`${ref_table}\` WHERE \`${ref_column}\`='${escaped_value}' LIMIT 1;"
  exists="$(db_query "${exists_sql}")"

  if [[ "${exists}" =~ ^[0-9]+$ ]] && [ "${exists}" -ge 1 ]; then
    printf '%s' "${escaped_value}"
    return 0
  fi

  warn "${env_key}='${raw_value}' not found in ${ref_table}.${ref_column}; using NULL to avoid FK violation"
  printf ''
}

discover_identity_provider() {
  log "Discovering identity provider config"

  db_query "SELECT identity_provider_id, code, description, protocol, matchpoint, IFNULL(icon_url,'') FROM identity_providers ORDER BY identity_provider_id;"
  db_query "SELECT identity_provider_id, REPLACE(REPLACE(config, CHAR(10), ' '), CHAR(13), ' ') AS config, REPLACE(REPLACE(mapping, CHAR(10), ' '), CHAR(13), ' ') AS mapping FROM identity_providers ORDER BY identity_provider_id;"
  db_query "SELECT identity_provider_domain_id, identity_provider_id, domain, update_on_auth, IFNULL(default_library_id,''), IFNULL(default_category_id,''), allow_opac, allow_staff, auto_register_opac, auto_register_staff FROM identity_provider_domains ORDER BY identity_provider_domain_id;"
}

apply_identity_provider() {
  local code description protocol matchpoint icon_url
  local c_key c_secret c_well_known c_scope
  local m_userid m_email m_firstname m_surname
  local domain update_on_auth default_library_id default_category_id allow_opac allow_staff auto_register_opac auto_register_staff
  local default_library_id_raw default_category_id_raw
  local idp_id domain_id

  code="$(sql_escape "${KOHA_IDP_CODE}")"
  description="$(sql_escape "${KOHA_IDP_DESCRIPTION}")"
  protocol="$(sql_escape "${KOHA_IDP_PROTOCOL}")"
  matchpoint="$(sql_escape "${KOHA_IDP_MATCHPOINT}")"
  icon_url="$(sql_escape "${KOHA_IDP_ICON_URL}")"

  c_key="$(sql_escape "${KOHA_IDP_CONFIG_KEY}")"
  c_secret="$(sql_escape "${KOHA_IDP_CONFIG_SECRET}")"
  c_well_known="$(sql_escape "${KOHA_IDP_CONFIG_WELL_KNOWN_URL}")"
  c_scope="$(sql_escape "${KOHA_IDP_CONFIG_SCOPE}")"

  m_userid="$(sql_escape "${KOHA_IDP_MAPPING_USERID}")"
  m_email="$(sql_escape "${KOHA_IDP_MAPPING_EMAIL}")"
  m_firstname="$(sql_escape "${KOHA_IDP_MAPPING_FIRSTNAME}")"
  m_surname="$(sql_escape "${KOHA_IDP_MAPPING_SURNAME}")"

  domain="$(sql_escape "${KOHA_IDP_DOMAIN}")"
  update_on_auth="${KOHA_IDP_UPDATE_ON_AUTH}"
  default_library_id_raw="${KOHA_IDP_DEFAULT_LIBRARY_ID}"
  default_category_id_raw="${KOHA_IDP_DEFAULT_CATEGORY_ID}"
  default_library_id="$(normalize_fk_value_for_identity_provider_domain "KOHA_IDP_DEFAULT_LIBRARY_ID" "default_library_id" "${default_library_id_raw}")"
  default_category_id="$(normalize_fk_value_for_identity_provider_domain "KOHA_IDP_DEFAULT_CATEGORY_ID" "default_category_id" "${default_category_id_raw}")"
  allow_opac="${KOHA_IDP_ALLOW_OPAC}"
  allow_staff="${KOHA_IDP_ALLOW_STAFF}"
  auto_register_opac="${KOHA_IDP_AUTO_REGISTER_OPAC}"
  auto_register_staff="${KOHA_IDP_AUTO_REGISTER_STAFF}"

  log "Applying identity provider: ${KOHA_IDP_CODE}"

  if ${DRY_RUN}; then
    log "DRY-RUN: skip DB update"
    return 0
  fi

  idp_id="$(db_query "SELECT identity_provider_id FROM identity_providers WHERE code='${code}' LIMIT 1;")"

  if [ -z "${idp_id}" ]; then
    db_query "
INSERT INTO identity_providers (code, description, protocol, config, mapping, matchpoint, icon_url)
VALUES (
  '${code}',
  '${description}',
  '${protocol}',
  JSON_OBJECT(
    'key','${c_key}',
    'secret','${c_secret}',
    'well_known_url','${c_well_known}',
    'scope','${c_scope}'
  ),
  JSON_OBJECT(
    'userid','${m_userid}',
    'email','${m_email}',
    'firstname','${m_firstname}',
    'surname','${m_surname}'
  ),
  '${matchpoint}',
  NULLIF('${icon_url}','')
);
"
    idp_id="$(db_query "SELECT identity_provider_id FROM identity_providers WHERE code='${code}' LIMIT 1;")"
  else
    db_query "
UPDATE identity_providers
SET description='${description}',
    protocol='${protocol}',
    config=JSON_OBJECT(
      'key','${c_key}',
      'secret','${c_secret}',
      'well_known_url','${c_well_known}',
      'scope','${c_scope}'
    ),
    mapping=JSON_OBJECT(
      'userid','${m_userid}',
      'email','${m_email}',
      'firstname','${m_firstname}',
      'surname','${m_surname}'
    ),
    matchpoint='${matchpoint}',
    icon_url=NULLIF('${icon_url}','')
WHERE identity_provider_id=${idp_id};
"
  fi

  domain_id="$(db_query "SELECT identity_provider_domain_id FROM identity_provider_domains WHERE identity_provider_id=${idp_id} AND domain='${domain}' LIMIT 1;")"
  if [ -z "${domain_id}" ]; then
    db_query "
INSERT INTO identity_provider_domains (
  identity_provider_id, domain, update_on_auth, default_library_id, default_category_id,
  allow_opac, allow_staff, auto_register_opac, auto_register_staff
) VALUES (
  ${idp_id},
  '${domain}',
  ${update_on_auth},
  NULLIF('${default_library_id}',''),
  NULLIF('${default_category_id}',''),
  ${allow_opac},
  ${allow_staff},
  ${auto_register_opac},
  ${auto_register_staff}
);
"
  else
    db_query "
UPDATE identity_provider_domains
SET update_on_auth=${update_on_auth},
    default_library_id=NULLIF('${default_library_id}',''),
    default_category_id=NULLIF('${default_category_id}',''),
    allow_opac=${allow_opac},
    allow_staff=${allow_staff},
    auto_register_opac=${auto_register_opac},
    auto_register_staff=${auto_register_staff}
WHERE identity_provider_domain_id=${domain_id};
"
  fi

  if [ "${KOHA_DISABLE_GOOGLE_OIDC}" = "true" ]; then
    db_query "
UPDATE systempreferences
SET value='0'
WHERE variable IN ('GoogleOpenIDConnect','GoogleOpenIDConnectAutoRegister','RESTOAuth2ClientCredentials');
UPDATE systempreferences
SET value=''
WHERE variable IN (
  'GoogleOAuth2ClientID',
  'GoogleOAuth2ClientSecret',
  'GoogleOpenIDConnectDefaultBranch',
  'GoogleOpenIDConnectDefaultCategory',
  'GoogleOpenIDConnectDomain'
);
"
    log "Google OIDC prefs disabled/cleared"
  fi
}

verify_identity_provider() {
  local code idp_id protocol matchpoint
  local google_openid_pref

  code="$(sql_escape "${KOHA_IDP_CODE}")"
  idp_id="$(db_query "SELECT identity_provider_id FROM identity_providers WHERE code='${code}' LIMIT 1;")"
  [ -n "${idp_id}" ] || die "Provider not found by KOHA_IDP_CODE=${KOHA_IDP_CODE}"

  protocol="$(db_query "SELECT protocol FROM identity_providers WHERE identity_provider_id=${idp_id};")"
  matchpoint="$(db_query "SELECT matchpoint FROM identity_providers WHERE identity_provider_id=${idp_id};")"

  [ "${protocol}" = "${KOHA_IDP_PROTOCOL}" ] || die "protocol mismatch: expected ${KOHA_IDP_PROTOCOL}, got ${protocol}"
  [ "${matchpoint}" = "${KOHA_IDP_MATCHPOINT}" ] || die "matchpoint mismatch: expected ${KOHA_IDP_MATCHPOINT}, got ${matchpoint}"

  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(config, '$.key')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_CONFIG_KEY}" ] || die "config.key mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(config, '$.secret')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_CONFIG_SECRET}" ] || die "config.secret mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(config, '$.well_known_url')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_CONFIG_WELL_KNOWN_URL}" ] || die "config.well_known_url mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(config, '$.scope')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_CONFIG_SCOPE}" ] || die "config.scope mismatch"

  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(mapping, '$.userid')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_MAPPING_USERID}" ] || die "mapping.userid mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(mapping, '$.email')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_MAPPING_EMAIL}" ] || die "mapping.email mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(mapping, '$.firstname')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_MAPPING_FIRSTNAME}" ] || die "mapping.firstname mismatch"
  [ "$(db_query "SELECT JSON_UNQUOTE(JSON_EXTRACT(mapping, '$.surname')) FROM identity_providers WHERE identity_provider_id=${idp_id};")" = "${KOHA_IDP_MAPPING_SURNAME}" ] || die "mapping.surname mismatch"

  [ "$(db_query "SELECT COUNT(*) FROM identity_provider_domains WHERE identity_provider_id=${idp_id} AND domain='$(sql_escape "${KOHA_IDP_DOMAIN}")';")" -ge 1 ] || die "identity_provider_domains row not found for configured domain"

  if [ "${KOHA_DISABLE_GOOGLE_OIDC}" = "true" ]; then
    google_openid_pref="$(db_query "SELECT IFNULL((SELECT value FROM systempreferences WHERE variable='GoogleOpenIDConnect' LIMIT 1),'');")"
    case "${google_openid_pref}" in
      0) ;;
      "")
        warn "GoogleOpenIDConnect preference not found; skipping strict 0-check"
        ;;
      *)
        die "GoogleOpenIDConnect is not 0 (got '${google_openid_pref}')"
        ;;
    esac
  fi

  log "Verification passed for provider ${KOHA_IDP_CODE}"
}

main() {
  parse_args "$@"
  load_env_file

  [ -n "${DB_ROOT_PASS:-}" ] || die "DB_ROOT_PASS is required in ${ENV_FILE}"
  [ -n "${DB_NAME:-}" ] || die "DB_NAME is required in ${ENV_FILE}"

  load_required_env

  ${DO_DISCOVER} && discover_identity_provider
  ${DO_APPLY} && apply_identity_provider
  ${DO_VERIFY} && verify_identity_provider

  log "Done: identity provider workflow"
}

main "$@"
