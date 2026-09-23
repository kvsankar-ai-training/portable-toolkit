# A proxy URL can contain user:password before @. Logs are copied when asking
# for help, so show only the address needed to diagnose routing.
function Format-ProxyAddress($Value) {
    if (-not $Value) { return $Value }
    try {
        $uri = [Uri] $Value
        if ($uri.IsAbsoluteUri -and $uri.Host) {
            return $uri.Scheme + '://' + $uri.Authority
        }
    } catch { }
    if ("$Value" -match '@') { return '(proxy address with credentials hidden)' }
    return "$Value"
}
