use std::fmt::{Display, Formatter};

use url::Url;

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub base_url: Url,
    pub allowed_origin: AllowedOrigin,
    pub allow_insecure_http: bool,
}

#[derive(Clone, Debug)]
pub struct AllowedOrigin {
    scheme: String,
    host: String,
    port: u16,
}

#[derive(Debug)]
pub enum ConfigError {
    MissingBaseUrl,
    InvalidBaseUrl(url::ParseError),
    UnsupportedScheme(String),
    MissingHost,
    InsecureHttpBlocked,
}

impl AppConfig {
    pub fn load() -> Result<Self, ConfigError> {
        let raw_base_url = option_env!("MEMOS_BASE_URL")
            .unwrap_or("")
            .trim()
            .to_string();

        if raw_base_url.is_empty() {
            return Err(ConfigError::MissingBaseUrl);
        }

        let base_url = Url::parse(&raw_base_url).map_err(ConfigError::InvalidBaseUrl)?;
        let allow_insecure_http = option_env!("ALLOW_INSECURE_HTTP")
            .map(parse_truthy)
            .unwrap_or(false);

        match base_url.scheme() {
            "https" => {}
            "http" => {
                if !cfg!(debug_assertions) || !allow_insecure_http {
                    return Err(ConfigError::InsecureHttpBlocked);
                }
            }
            other => {
                return Err(ConfigError::UnsupportedScheme(other.to_string()));
            }
        }

        let allowed_origin =
            AllowedOrigin::from_url(&base_url).ok_or(ConfigError::MissingHost)?;

        Ok(Self {
            base_url,
            allowed_origin,
            allow_insecure_http,
        })
    }

    pub fn allows_in_app(&self, candidate: &Url) -> bool {
        self.allowed_origin.matches(candidate)
    }
}

impl AllowedOrigin {
    pub fn from_url(url: &Url) -> Option<Self> {
        Some(Self {
            scheme: url.scheme().to_string(),
            host: url.host_str()?.to_ascii_lowercase(),
            port: url.port_or_known_default()?,
        })
    }

    pub fn as_string(&self) -> String {
        format!("{}://{}{}", self.scheme, self.host, self.port_suffix())
    }

    pub fn matches(&self, candidate: &Url) -> bool {
        let Some(host) = candidate.host_str() else {
            return false;
        };
        let Some(port) = candidate.port_or_known_default() else {
            return false;
        };

        self.scheme == candidate.scheme()
            && self.host.eq_ignore_ascii_case(host)
            && self.port == port
    }

    fn port_suffix(&self) -> String {
        let is_default = matches!(
            (self.scheme.as_str(), self.port),
            ("http", 80) | ("https", 443)
        );

        if is_default {
            String::new()
        } else {
            format!(":{}", self.port)
        }
    }
}

impl Display for ConfigError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingBaseUrl => {
                write!(
                    f,
                    "MEMOS_BASE_URL is required. Set it in .env.android.debug or .env.android.release before building."
                )
            }
            Self::InvalidBaseUrl(error) => write!(f, "MEMOS_BASE_URL is not a valid URL: {error}"),
            Self::UnsupportedScheme(scheme) => write!(
                f,
                "MEMOS_BASE_URL must use http or https. Received unsupported scheme: {scheme}."
            ),
            Self::MissingHost => write!(
                f,
                "MEMOS_BASE_URL must include a host so the in-app domain allowlist can be derived."
            ),
            Self::InsecureHttpBlocked => write!(
                f,
                "HTTP MEMOS_BASE_URL values are blocked by default. Use https, or set ALLOW_INSECURE_HTTP=1 for debug builds only."
            ),
        }
    }
}

impl std::error::Error for ConfigError {}

fn parse_truthy(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}
