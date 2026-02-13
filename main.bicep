// ============================================================================
// メインオーケストレーションファイル
// Application Gateway と VNet 構成シナリオ
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// パラメータ
// ============================================================================

@description('Azure リージョン')
param location string = resourceGroup().location

@description('環境名 (dev, stg, prod)')
param environment string = 'prod'

@description('プロジェクト名 (リソース名のプレフィックス)')
param projectName string = 'appgw'

// Network パラメータ
@description('VNet1 (AppGW専用) アドレス空間')
param vnet1AddressPrefix string = '10.0.0.0/16'

@description('VNet1 AppGW サブネットプレフィックス')
param vnet1AppGwSubnetPrefix string = '10.0.1.0/24'

@description('VNet2 (Backend VM用) アドレス空間')
param vnet2AddressPrefix string = '10.1.0.0/16'

@description('VNet2 VM サブネットプレフィックス')
param vnet2VmSubnetPrefix string = '10.1.1.0/24'

@description('VNet3 (テスト・管理用) アドレス空間')
param vnet3AddressPrefix string = '10.2.0.0/16'

@description('VNet3 テストVM サブネットプレフィックス')
param vnet3VmSubnetPrefix string = '10.2.1.0/24'

// VM パラメータ
@description('VM サイズ')
param vmSize string = 'Standard_B2s'

@description('管理者ユーザー名')
param adminUsername string = 'azureuser'

@description('SSH 公開鍵')
@secure()
param sshPublicKey string

@description('Test VM 用の SSH 秘密鍵 (VM1への接続用、オプション)')
@secure()
param sshPrivateKey string = ''

// Application Gateway パラメータ
@description('Application Gateway 最小キャパシティ')
param appGwAutoScaleMinCapacity int = 2

@description('Application Gateway 最大キャパシティ')
param appGwAutoScaleMaxCapacity int = 10

// ============================================================================
// モジュール: ネットワーク
// ============================================================================

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    projectName: projectName
    environment: environment
    vnet1AddressPrefix: vnet1AddressPrefix
    vnet1AppGwSubnetPrefix: vnet1AppGwSubnetPrefix
    vnet2AddressPrefix: vnet2AddressPrefix
    vnet2VmSubnetPrefix: vnet2VmSubnetPrefix
    vnet3AddressPrefix: vnet3AddressPrefix
    vnet3VmSubnetPrefix: vnet3VmSubnetPrefix
  }
}

// ============================================================================
// モジュール: Application Gateway
// ============================================================================

module appgw 'modules/appgw.bicep' = {
  name: 'appgw-deployment'
  params: {
    location: location
    projectName: projectName
    environment: environment
    appGwSubnetId: network.outputs.appGwSubnetId
    backendVmNicId: vm1.outputs.nicId
    backendVmPrivateIp: vm1.outputs.privateIp
    autoScaleMinCapacity: appGwAutoScaleMinCapacity
    autoScaleMaxCapacity: appGwAutoScaleMaxCapacity
  }
}

// ============================================================================
// モジュール: Backend VM (VM1)
// ============================================================================

module vm1 'modules/vm.bicep' = {
  name: 'vm1-deployment'
  params: {
    location: location
    projectName: projectName
    environment: environment
    vmName: 'vm-web1'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: network.outputs.vm1SubnetId
    enablePublicIp: false
    cloudInitData: loadTextContent('cloud-init/vm1-nginx.yaml')
  }
}

// ============================================================================
// モジュール: Test VM (VM-Test)
// ============================================================================

module vmTest 'modules/vm.bicep' = {
  name: 'vmtest-deployment'
  params: {
    location: location
    projectName: projectName
    environment: environment
    vmName: 'vm-test'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: network.outputs.vmTestSubnetId
    enablePublicIp: true
    cloudInitData: loadTextContent('cloud-init/vmtest-tools.yaml')
    sshPrivateKey: sshPrivateKey
  }
}

// ============================================================================
// 出力
// ============================================================================

@description('Application Gateway の Public IP アドレス')
output appGwPublicIp string = appgw.outputs.publicIpAddress

@description('Application Gateway の FQDN')
output appGwFqdn string = appgw.outputs.publicIpFqdn

@description('Test VM の Public IP アドレス')
output testVmPublicIp string = vmTest.outputs.publicIpAddress

@description('Test VM の FQDN')
output testVmFqdn string = vmTest.outputs.publicIpFqdn

@description('Backend VM1 の Private IP アドレス')
output vm1PrivateIp string = vm1.outputs.privateIp

@description('Test VM への SSH 接続コマンド')
output testVmSshCommand string = 'ssh -i ~/.ssh/vm-ssh-key ${adminUsername}@${vmTest.outputs.publicIpAddress}'

@description('Test VM から VM1 への SSH 接続コマンド')
output vm1SshCommand string = 'ssh -i ~/.ssh/vm-ssh-key ${adminUsername}@${vm1.outputs.privateIp}'

@description('Application Gateway への curl テストコマンド')
output curlTestCommand string = 'curl http://${appgw.outputs.publicIpAddress}'
