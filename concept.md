# Azure Application Gateway と VNet 構成シナリオ

## 概要
このシナリオでは、Azure Application Gateway を使用して独立した VNet に配置された VM1 へトラフィックをルーティングします。Application Gateway は専用 VNet に配置し、Backend の VM とは VNet ピアリングで接続します。VNet3 はテスト・管理用途で使用し、Application Gateway へのテストリクエスト送信や、VNet ピアリング経由での VM1 の管理アクセスに利用します。

## アーキテクチャ構成

```
                    Internet
                        |
                        v
        +-------------------------------+
        |  VNet1 (10.0.0.0/16)         |
        |  Application Gateway 専用     |
        |                               |
        |  +-------------------------+  |
        |  | Application Gateway     |  |
        |  +-------------------------+  |
        +-------------------------------+
                        |
                        | VNet Peering
                        v
        +-------------------------------+
        |  VNet2 (10.1.0.0/16)         |
        |  Backend VM 用               |
        |                               |
        |  +-------------------------+  |
        |  | VM1 (Backend)           |  |  <-- Backend Pool ターゲット
        |  | 10.1.1.4                |  |
        |  +-------------------------+  |
        +-------------------------------+
                        ^
                        | VNet Peering (管理用)
                        |
        +-------------------------------+
        |  VNet3 (10.2.0.0/16)         |
        |  テスト・管理用               |
        |                               |
        |  +-------------------------+  |
        |  | VM-Test                 |  |
        |  | 10.2.1.4                |  |
        |  | (JIT経由で外部接続)      |  |
        |  +-------------------------+  |
        +-------------------------------+

接続フロー:
1. Internet → VNet1 (AppGW) → VNet2 (VM1): HTTP/HTTPS トラフィック
2. Internet → VNet3 (VM-Test) via JIT: SSH 管理アクセス
3. VNet3 (VM-Test) → VNet2 (VM1) via Peering: SSH メンテナンス
4. VNet3 (VM-Test) → VNet1 (AppGW Public IP): curl テスト
```

## 必要なリソース

### 1. SSH Key Pair (VM認証用)
- **名前**: `vm-ssh-key`
- **タイプ**: RSA 4096-bit
- **用途**: VM1 (Backend) と VM-Test の両方で使用
- **生成方法**:
  ```bash
  # ローカルまたは Azure Cloud Shell で生成
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm-ssh-key -C "azureuser@azure-vms"
  ```
- **公開鍵の配置**:
  - VM1: `/home/azureuser/.ssh/authorized_keys`
  - VM-Test: `/home/azureuser/.ssh/authorized_keys`
- **秘密鍵の管理**: Azure Key Vault に保存（推奨）または安全なローカル環境に保管
- **Bicep での指定**: cloud-init または Custom Script Extension で公開鍵を設定

### 2. Virtual Network 1 (Application Gateway 専用)
- **名前**: `vnet-appgw`
- **アドレス空間**: `10.0.0.0/16`
- **サブネット**:
  - Application Gateway サブネット: `10.0.1.0/24` (名前: `snet-appgw`)
- **用途**: Application Gateway 専用 VNet

### 2. Virtual Network 2 (Backend VM 用)
- **名前**: `vnet-backend`
- **アドレス空間**: `10.1.0.0/16`
- **サブネット**:
  - VM1 サブネット: `10.1.1.0/24` (名前: `snet-vm1`)
- **用途**: Backend の Web サーバー VM を配置

### 3. Virtual Network 3 (テスト・管理用)
- **名前**: `vnet-test`
- **アドレス空間**: `10.2.0.0/16`
- **サブネット**:
  - テスト VM サブネット: `10.2.1.0/24` (名前: `snet-test`)
- **用途**: テストリクエスト送信と管理アクセス

### 4. VNet Peering
#### Peering 1: vnet-appgw ↔ vnet-backend
- **Peering 1a**: vnet-appgw → vnet-backend
- **Peering 1b**: vnet-backend → vnet-appgw
- **設定**:
  - Allow Virtual Network Access: `true`
  - Allow Forwarded Traffic: `true`
  - Allow Gateway Transit: `false`
  - Use Remote Gateways: `false`
- **用途**: Application Gateway から Backend Pool (VM1) へのアクセス

#### Peering 2: vnet-test ↔ vnet-backend
- **Peering 2a**: vnet-test → vnet-backend
- **Peering 2b**: vnet-backend → vnet-test
- **設定**:
  - Allow Virtual Network Access: `true`
  - Allow Forwarded Traffic: `true`
  - Allow Gateway Transit: `false`
  - Use Remote Gateways: `false`
- **用途**: Test VM から VM1 への管理アクセス (SSH/RDP)

### 5. Just-In-Time (JIT) VM Access
- **対象 VM**: VM-Test (VNet3)
- **必要なサービス**: Microsoft Defender for Cloud (無料版または有料版)
- **設定**:
  - JIT ポリシーを有効化
  - 許可するポート: SSH (22)
  - 最大リクエスト時間: 3時間
  - 許可される送信元 IP: 管理者の IP アドレス範囲
- **アクセスフロー**:
  1. Azure Portal または Azure CLI で JIT アクセスをリクエスト
  2. 指定した時間内に限り、指定 IP から SSH 接続が可能
  3. 時間経過後、NSG ルールが自動的に削除される
- **注意**: JIT を使用するため、Test VM の NSG には常時開放の SSH ルールは不要

### 6. Network Security Group (NSG)
#### NSG for Application Gateway Subnet (VNet1)
- **名前**: `nsg-appgw`
- **インバウンド規則**:
  - HTTP: Port 80 (Source: Internet, Priority: 100)
  - HTTPS: Port 443 (Source: Internet, Priority: 110)
  - GatewayManager: Port 65200-65535 (Source: GatewayManager, Priority: 120)

#### NSG for VM1 Subnet (VNet2)
- **名前**: `nsg-vm1`
- **インバウンド規則**:
  - HTTP: Port 80 (Source: Application Gateway サブネット `10.0.1.0/24`, Priority: 100)
  - SSH/RDP: Port 22/3389 (Source: VNet3 テストサブネット `10.2.1.0/24`, Priority: 200)

#### NSG for Test VM Subnet (VNet3)
- **名前**: `nsg-test`
- **インバウンド規則**:
  - SSH ルールは JIT により動的に追加されるため、静的ルールは不要
  - JIT が無効な場合の代替: SSH Port 22 (Source: 管理者 IP, Priority: 100)
- **アウトバウンド規則**:
  - Application Gateway への HTTP/HTTPS アクセスを許可 (デフォルトで許可)
  - VNet2 (Backend) への SSH アクセスを許可 (デフォルトで許可)

### 7. Public IP Address
#### Application Gateway 用
- **名前**: `pip-appgw`
- **SKU**: `Standard`
- **Allocation**: `Static`
- **Tier**: `Regional`
- **用途**: Application Gateway の Frontend IP

#### Test VM 用
- **名前**: `pip-test`
- **SKU**: `Standard`
- **Allocation**: `Static`
- **Tier**: `Regional`
- **用途**: JIT 経由での SSH 接続

### 8. Application Gateway
- **名前**: `appgw-prod`
- **SKU**: `Standard_v2` (最も低コストなオプション)
- **Tier**: `Standard_v2`
- **Capacity**: `2` (Autoscaling: Min=2, Max=10)
- **注記**: WAF 機能が必要な場合は `WAF_v2` SKU にアップグレード可能
- **Frontend IP Configuration**:
  - Public IP: `pip-appgw`
- **Backend Pool**:
  - 名前: `backend-pool-vms`
  - ターゲット: VM1 の NIC (VNet2 の VM、VNet ピアリング経由でアクセス)
- **HTTP Settings**:
  - 名前: `http-settings`
  - Protocol: `HTTP`
  - Port: `80`
  - Cookie-based affinity: `Disabled`
  - Request timeout: `30` 秒
- **Listener**:
  - 名前: `http-listener`
  - Frontend IP: Public
  - Protocol: `HTTP`
  - Port: `80`
- **Routing Rule**:
  - 名前: `rule-basic`
  - Rule type: `Basic`
  - Listener: `http-listener`
  - Backend pool: `backend-pool-vms`
  - HTTP settings: `http-settings`

### 9. Virtual Machines

#### VM1 (VNet2 - Backend)
- **名前**: `vm-web1`
- **サイズ**: `Standard_B2ps_v2` (Arm64 アーキテクチャ対応)
- **OS**: `Ubuntu 24.04 LTS` (Canonical、offer: `ubuntu-24_04-lts`, sku: `minimal-arm64`)
- **ストレージ**: Premium_LRS (30GB)
- **Network Interface**:
  - VNet: `vnet-backend`
  - サブネット: `snet-vm1`
  - Private IP: 動的または `10.1.1.4`
  - Public IP: なし (Application Gateway 経由でアクセス)
- **管理者**:
  - ユーザー名: `azureuser`
  - 認証: SSH キー (`vm-ssh-key` の公開鍵を使用)
- **インストールソフトウェア** (cloud-init):
  ```yaml
  #cloud-config
  package_update: true
  package_upgrade: true
  packages:
    - nginx
    - curl
    - net-tools
  runcmd:
    - systemctl start nginx
    - systemctl enable nginx
    - |
      cat > /var/www/html/index.html <<EOF
      <!DOCTYPE html>
      <html lang="ja">
      <head>
          <meta charset="UTF-8">
          <title>Backend VM1</title>
          <style>
              body { font-family: Arial, sans-serif; margin: 50px; background-color: #f0f0f0; }
              .container { background-color: white; padding: 30px; border-radius: 10px; }
              h1 { color: #0078d4; }
          </style>
      </head>
      <body>
          <div class="container">
              <h1>🚀 Backend VM1 - Azure Application Gateway Demo</h1>
              <p><strong>Hostname:</strong> $(hostname)</p>
              <p><strong>Private IP:</strong> $(hostname -I | awk '{print $1}')</p>
          </div>
      </body>
      </html>
      EOF
  ```
  注: SSH公開鍵はBicepのlinuxConfiguration設定で自動的に配置されます
- **用途**: Backend Web サーバー

#### VM-Test (VNet3 - テスト・管理用)
- **名前**: `vm-test`
- **サイズ**: `Standard_B2ps_v2` (Arm64 アーキテクチャ対応)
- **OS**: `Ubuntu 24.04 LTS` (Canonical、offer: `ubuntu-24_04-lts`, sku: `minimal-arm64`)
- **ストレージ**: Premium_LRS (30GB)
- **Network Interface**:
  - VNet: `vnet-test`
  - サブネット: `snet-test`
  - Private IP: 動的または `10.2.1.4`
  - Public IP: `pip-test` (JIT 経由での SSH アクセス用、必須)
- **管理者**:
  - ユーザー名: `azureuser`
  - 認証: SSH キー (`vm-ssh-key` の公開鍵を使用)
- **インストールソフトウェア** (cloud-init):
  ```yaml
  #cloud-config
  package_update: true
  package_upgrade: true
  packages:
    - curl
    - wget
    - jq
    - net-tools
    - dnsutils
    - tcpdump
    - nmap
  runcmd:
    - echo "Test VM setup completed at $(date)" > /home/azureuser/setup-complete.txt
  ```
  注: SSH公開鍵はBicepのlinuxConfiguration設定で自動的に配置されます
- **SSH 秘密鍵の配置**:
  - Test VM に秘密鍵 (`vm-ssh-key`) を Custom Script Extension で自動配置
  - 配置先: `/home/azureuser/.ssh/vm-ssh-key` (パーミッション: 600)
  - デプロイ時にパラメータとして秘密鍵を指定: `--parameters sshPrivateKey="$(cat ~/.ssh/vm-ssh-key)"`
- **用途**:
  - Application Gateway への HTTP/HTTPS テストリクエスト送信 (curl)
  - VNet ピアリング経由での VM1 への管理アクセス (SSH)
  - Backend VM のメンテナンス作業

## パラメータ化すべき設定値

```bicep
// 基本設定
param location string = 'japaneast'
param environment string = 'prod'

// Network 設定
// VNet1: Application Gateway 専用
param vnet1AddressPrefix string = '10.0.0.0/16'
param vnet1AppGwSubnetPrefix string = '10.0.1.0/24'

// VNet2: Backend VM 用
param vnet2AddressPrefix string = '10.1.0.0/16'
param vnet2VmSubnetPrefix string = '10.1.1.0/24'

// VNet3: テスト・管理用
param vnet3AddressPrefix string = '10.2.0.0/16'
param vnet3VmSubnetPrefix string = '10.2.1.0/24'

// VM 設定
param vmSize string = 'Standard_B2ps_v2'  // Arm64 アーキテクチャ対応
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string  // SSH 公開鍵 (vm-ssh-key.pub の内容)
@secure()
param sshPrivateKey string = ''  // Test VM 用の SSH 秘密鍵 (オプション)

// Application Gateway 設定
param appGwCapacity int = 2
param appGwAutoScaleMinCapacity int = 2
param appGwAutoScaleMaxCapacity int = 10
```

## Agent への指示例

```markdown
上記の concept.md に記載されたシナリオに基づいて、以下の Bicep ファイルを作成してください:

1. main.bicep - メインのオーケストレーションファイル
2. modules/network.bicep - VNet、サブネット、NSG、VNet ピアリングを定義
3. modules/appgw.bicep - Application Gateway と Public IP を定義
4. modules/vm.bicep - Virtual Machine、NIC を定義

要件:
- モジュール化された構成にする
- パラメータファイル (main.bicepparam) も作成する
- ベストプラクティスに従った命名規則を使用する
- 3つの独立した VNet を作成する (AppGW 専用、Backend VM 用、テスト用)
- VNet1 と VNet2 間、VNet2 と VNet3 間に VNet ピアリングを設定する
- SSH Key Pair を事前に生成し、パラメータとして公開鍵を渡す
- 両方の VM で同じ SSH 公開鍵を authorized_keys に設定
- Test VM に秘密鍵を配置 (VM1 への SSH 接続用)
- Test VM に Public IP を割り当て (JIT アクセス用)
- Microsoft Defender for Cloud の JIT ポリシーを Test VM に適用
- 出力値で Application Gateway の Public IP アドレスと Test VM の Public IP を返す
- VM1 (VNet2) には nginx をインストールし、簡単な HTML ページを配置する cloud-init を含める
- VM-Test (VNet3) には curl、wget、jq などのテストツールをインストールする cloud-init を含める
- Backend Pool には VNet2 の VM1 のみを含める
- Test VM の NSG は JIT により動的に管理されるため、静的な SSH ルールは不要
```

## デプロイ前の準備

### 1. Azure CLI のセットアップと認証
```bash
# Azure CLI にログイン
az login

# 利用可能なサブスクリプション一覧を表示
az account list --output table

# ターゲットとするサブスクリプションを設定
az account set --subscription "<サブスクリプションIDまたは名前>"

# 現在のサブスクリプションを確認
az account show --output table

# 接続テスト: リソースグループの一覧を取得
az group list --output table

# (オプション) デプロイ先のリソースグループを作成
az group create --name rg-appgw-demo --location japaneast
```

### 2. SSH Key Pair の生成
```bash
# SSH Key Pair を生成
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vm-ssh-key -C "azureuser@azure-vms"

# 公開鍵の内容を確認 (Bicep パラメータに使用)
cat ~/.ssh/vm-ssh-key.pub

# (オプション) Azure Key Vault に秘密鍵を保存
az keyvault secret set --vault-name <KeyVault名> \
  --name vm-ssh-private-key \
  --file ~/.ssh/vm-ssh-key
```

## 検証手順

### 1. インターネットからのアクセステスト
1. Bicep ファイルをデプロイ後、Application Gateway の Public IP にアクセス
2. VM1 の Web サーバーが正常に応答することを確認
3. Azure Portal で Backend Health を確認し、VM1 が Healthy であることを検証

### 2. VNet3 (テスト VM) からのアクセステスト

#### 2.1. JIT を使用して Test VM に接続

##### Step 1: Microsoft Defender for Cloud を有効化
1. [Azure Portal](https://portal.azure.com) にサインイン
2. 検索バーで「**Microsoft Defender for Cloud**」を検索して選択
3. 左側メニューから「**環境設定**」を選択
4. 対象のサブスクリプションをクリック
5. 「**Defender プラン**」で「**サーバー**」を「**オン**」に設定（無料試用版または有料版）
6. 「**保存**」をクリック

##### Step 2: VM-Test で JIT アクセスを有効化
1. Azure Portal で「**仮想マシン**」を検索して選択
2. 対象の VM「**vm-test**」をクリック
3. 左側メニューから「**構成**」→「**Just-In-Time VM アクセス**」を選択
   - または Microsoft Defender for Cloud → 「**ワークロード保護**」→「**Just-In-Time VM アクセス**」からアクセス
4. 「**JIT VM アクセスを有効にする**」をクリック
5. JIT ポリシーを設定:
   - **ポート 22 (SSH)**: 
     - 最大リクエスト時間: **3 時間**
     - 許可される送信元 IP: **マイ IP** または特定の IP 範囲を指定
6. 「**保存**」をクリック

##### Step 3: JIT アクセスをリクエスト
1. VM「**vm-test**」の画面で「**接続**」をクリック
2. 「**マイ IP**」タブを選択（または「Just-In-Time」タブ）
3. 「**アクセス権の要求**」をクリック
4. リクエストの詳細を設定:
   - **ポート**: 22 (SSH)
   - **送信元 IP**: マイ IP（自動検出）または手動で IP を入力
   - **時間範囲**: 3 時間（またはカスタム設定）
5. 「**ポートを開く**」をクリック
6. ステータスが「**承認済み**」になるまで待機（通常は数秒）

##### Step 4: SSH 接続
許可された時間内にローカル端末から Test VM に SSH 接続:
```bash
# ローカル端末から Test VM に接続
ssh -i ~/.ssh/vm-ssh-key azureuser@<Test-VM-Public-IP>
```

**注意事項**:
- JIT アクセスは指定した時間が経過すると自動的に無効化されます
- 再度接続が必要な場合は、Step 3 からアクセス要求を再実行してください
- Azure Portal の「アクティビティ ログ」でアクセス履歴を確認できます

#### 2.2. Test VM から Application Gateway への curl テスト
1. Test VM にログイン後、AppGW の Public IP に HTTP リクエストを送信:
   ```bash
   # AppGW の Public IP を確認
   APPGW_IP="<AppGW-Public-IP>"
   
   # 基本的な curl テスト
   curl -v http://$APPGW_IP
   
   # 複数回リクエストして応答を確認
   for i in {1..10}; do
     echo "Request $i:"
     curl -s http://$APPGW_IP | grep -o "<h1>.*</h1>"
     sleep 1
   done
   
   # ヘッダー情報も含めて確認
   curl -I http://$APPGW_IP
   ```
2. Backend VM1 が正常に応答していることを確認
3. Application Gateway のログで正常なルーティングを確認

#### 2.3. Test VM から Backend VM1 への SSH 接続
1. Test VM から VNet ピアリング経由で VM1 に SSH 接続:
   ```bash
   # Test VM (VNet3) から VM1 (VNet2) へ SSH
   ssh -i ~/.ssh/vm-ssh-key azureuser@10.1.1.4
   ```
2. VM1 にログイン後、メンテナンス作業を実施:
   ```bash
   # nginx のステータス確認
   sudo systemctl status nginx
   
   # ログ確認
   sudo tail -f /var/log/nginx/access.log
   
   # 設定変更 (例: index.html の更新)
   sudo nano /var/www/html/index.html
   
   # nginx 再起動
   sudo systemctl restart nginx
   ```
3. Test VM に戻り、再度 curl テストで変更を確認:
   ```bash
   curl http://$APPGW_IP
   ```

### 3. Backend Pool の確認
1. Azure Portal で Application Gateway の Backend Pool を確認
2. Backend Pool に VM1 (VNet2) のみが含まれていることを検証
3. VNet1 には Application Gateway のみが存在し、VM は配置されていないことを確認

### 4. VNet 構成の確認
1. VNet1 (vnet-appgw): Application Gateway サブネットのみ
2. VNet2 (vnet-backend): VM1 が配置されている
3. VNet3 (vnet-test): Test VM が配置されている
4. VNet Peering が正しく構成されている (VNet1↔VNet2、VNet2↔VNet3)
