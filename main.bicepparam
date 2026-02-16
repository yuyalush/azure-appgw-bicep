// ============================================================================
// パラメータファイル
// main.bicep 用のパラメータ値を定義
// ============================================================================

using './main.bicep'

// ============================================================================
// 基本設定
// ============================================================================

param location = 'japaneast'
param environment = 'prod'
param projectName = 'appgw'

// ============================================================================
// ネットワーク設定
// ============================================================================

// VNet1: Application Gateway 専用
param vnet1AddressPrefix = '10.0.0.0/16'
param vnet1AppGwSubnetPrefix = '10.0.1.0/24'

// VNet2: Backend VM 用
param vnet2AddressPrefix = '10.1.0.0/16'
param vnet2VmSubnetPrefix = '10.1.1.0/24'

// VNet3: テスト・管理用
param vnet3AddressPrefix = '10.2.0.0/16'
param vnet3VmSubnetPrefix = '10.2.1.0/24'

// ============================================================================
// VM 設定
// ============================================================================

param vmSize = 'Standard_B2ps_v2'  // Arm64 アーキテクチャ対応
param adminUsername = 'azureuser'

// SSH 公開鍵
// 注意: 実際のデプロイ前に、以下のコマンドで SSH キーを生成してください:
//   ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm-ssh-key -C "azureuser@azure-vms"
// 
// 生成後、公開鍵の内容を以下に貼り付けてください:
//   cat ~/.ssh/vm-ssh-key.pub
param sshPublicKey = 'PASTE_YOUR_SSH_PUBLIC_KEY_HERE'

// SSH 秘密鍵 (Test VM 用、推奨)
// 設定すると Custom Script Extension により Test VM の
// /home/azureuser/.ssh/vm-ssh-key に自動配置されます (パーミッション: 600)
// これにより connect-vm1.sh スクリプトで VM1 への SSH 接続がすぐに利用可能になります
// 空のままにした場合は、デプロイ後に SCP 等で手動転送が必要です
param sshPrivateKey = ''

// ============================================================================
// Application Gateway 設定
// ============================================================================

param appGwAutoScaleMinCapacity = 2
param appGwAutoScaleMaxCapacity = 10
