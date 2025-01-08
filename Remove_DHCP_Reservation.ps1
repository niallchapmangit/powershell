<#
.SYNOPSIS
    Removes a DHCP reservation from a specified server and subnet.

.DESCRIPTION
    This PowerShell script removes an IP reservation from a DHCP server.
    It is designed to run on a ServiceNow MID server or any other environment with proper permissions.

.PARAMETER dhcp_server
    The hostname or IP address of the DHCP server.

.PARAMETER subnet
    The subnet where the reservation exists.

.PARAMETER reservation_ip
    The reserved IP address to remove.

.EXAMPLE
    Remove-DHCPReservation -dhcp_server "dhcp.example.com" -subnet "192.168.1.0" -reservation_ip "192.168.1.100"
#>

param (
    [string]$dhcp_server,   # The DHCP Server
    [string]$subnet,        # Subnet where the reservation exists
    [string]$reservation_ip # The reserved IP address to remove
)

function Connect-DhcpServer {
    param (
        [string]$dhcp_server
    )

    Write-Host "Connecting to DHCP server $dhcp_server..." -ForegroundColor Cyan
    try {
        # Example connectivity test
        $lease = Get-DhcpServerv4Lease -ComputerName $dhcp_server | Select-Object -First 1
        if (-not $lease) {
            throw "No leases found on DHCP server $dhcp_server."
        }
        Write-Host "Successfully connected to DHCP server $dhcp_server." -ForegroundColor Green
    } catch {
        throw "Failed to connect to DHCP server $dhcp_server. Error: $_"
    }
}

function Remove-DhcpReservation {
    param (
        [string]$dhcp_server,
        [string]$subnet,
        [string]$reservation_ip
    )

    Write-Host "Checking for existing reservation for IP $reservation_ip in subnet $subnet..." -ForegroundColor Cyan
    try {
        # Check if the reservation exists
        $reservation = Get-DhcpServerv4Reservation -ComputerName $dhcp_server -ScopeId $subnet | Where-Object { $_.IPAddress -eq $reservation_ip }
        if (-not $reservation) {
            throw "No reservation found for IP address $reservation_ip in subnet $subnet."
        }

        # Remove the reservation
        Write-Host "Removing reservation for IP $reservation_ip..." -ForegroundColor Green
        Remove-DhcpServerv4Reservation -ComputerName $dhcp_server -ScopeId $subnet -IPAddress $reservation_ip -Confirm:$false
        Write-Host "Reservation successfully removed." -ForegroundColor Green

        return @{ reservation_ip = $reservation_ip; subnet = $subnet; server = $dhcp_server }
    } catch {
        throw "Error removing DHCP reservation: $_"
    }
}

try {
    # Validate required parameters
    if (-not $reservation_ip -or -not $subnet -or -not $dhcp_server) {
        throw "All required parameters must be provided."
    }

    # Connect to the DHCP server and remove the reservation
    Connect-DhcpServer -dhcp_server $dhcp_server
    $removal_details = Remove-DhcpReservation -dhcp_server $dhcp_server -subnet $subnet -reservation_ip $reservation_ip

    # Output success message
    $output = @{
        status  = "success"
        message = "Reservation successfully removed."
        details = $removal_details
    }
    Write-Output (ConvertTo-Json $output -Depth 10)
    exit 0
} catch {
    # Output failure message
    $output = @{
        status  = "failure"
        message = "Failed to remove the IP reservation."
        error   = $_.Exception.Message
        details = @{
            reservation_ip = $reservation_ip
            subnet         = $subnet
            server         = $dhcp_server
        }
    }
    Write-Output (ConvertTo-Json $output -Depth 10)
    exit 1
}
