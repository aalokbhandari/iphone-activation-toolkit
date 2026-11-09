param([Parameter(Mandatory = $true)][string]$SourcePath)
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText($SourcePath)
$original = 'curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 0);'
if ([regex]::Matches($source, [regex]::Escape($original)).Count -ne 1) {
    throw 'The reviewed upstream transport source has changed; the hardening patch was not applied.'
}
$replacement = @'
curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 1L);
	curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, 2L);
	const char *tr4mpass_ca_bundle = getenv("TR4MPASS_CA_BUNDLE");
	if (tr4mpass_ca_bundle && *tr4mpass_ca_bundle) {
		curl_easy_setopt(handle, CURLOPT_CAINFO, tr4mpass_ca_bundle);
	}
	curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, 15L);
	curl_easy_setopt(handle, CURLOPT_TIMEOUT, 120L);
	curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "https");
	curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, "https");
'@
[IO.File]::WriteAllText($SourcePath, $source.Replace($original, $replacement), [Text.UTF8Encoding]::new($false))
Write-Host 'Applied transport patch: TLS peer/host verification, explicit CA bundle, HTTPS-only redirects, and request timeouts.'
