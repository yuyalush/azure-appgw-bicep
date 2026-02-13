// ============================================================================
// Application Gateway モジュール
// Application Gateway と Public IP を定義
// ============================================================================

@description('Azure リージョン')
param location string

@description('プロジェクト名')
param projectName string

@description('環境名')
param environment string

@description('Application Gateway サブネット ID')
param appGwSubnetId string

@description('Backend VM の NIC ID')
param backendVmNicId string

@description('Backend VM の Private IP')
param backendVmPrivateIp string

@description('自動スケーリング最小キャパシティ')
param autoScaleMinCapacity int = 2

@description('自動スケーリング最大キャパシティ')
param autoScaleMaxCapacity int = 10

// ============================================================================
// Public IP Address for Application Gateway
// ============================================================================

resource pipAppGw 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-${projectName}-appgw-${environment}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${projectName}-appgw-${environment}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// ============================================================================
// Application Gateway
// ============================================================================

resource appGw 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: 'appgw-${projectName}-${environment}'
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      minCapacity: autoScaleMinCapacity
      maxCapacity: autoScaleMaxCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: appGwSubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: pipAppGw.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'http-port'
        properties: {
          port: 80
        }
      }
      {
        name: 'https-port'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-pool-vms'
        properties: {
          backendAddresses: [
            {
              ipAddress: backendVmPrivateIp
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          pickHostNameFromBackendAddress: true
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', 'appgw-${projectName}-${environment}', 'health-probe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'appgw-${projectName}-${environment}', 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'appgw-${projectName}-${environment}', 'http-port')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule-basic'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'appgw-${projectName}-${environment}', 'http-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'appgw-${projectName}-${environment}', 'backend-pool-vms')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'appgw-${projectName}-${environment}', 'http-settings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          protocol: 'Http'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
  }
}

// ============================================================================
// 出力
// ============================================================================

output applicationGatewayId string = appGw.id
output publicIpAddress string = pipAppGw.properties.ipAddress
output publicIpFqdn string = pipAppGw.properties.dnsSettings.fqdn
