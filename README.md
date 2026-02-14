# Jetson向け GStreamer RTP/AV1 セットアップ手順 (JP6.2)

このリポジトリは、Jetson環境で `nvv4l2av1enc` を使ったAV1ハードウェアエンコードと、
`rtpav1pay` / `rtpav1depay` によるRTP送受信を再現できるようにした手順です。

本手順は **既存環境を壊さない** ことを優先し、
システムのGStreamer本体は更新せずに、`gst-plugins-rs` をローカルビルドして使います。

## 対象と前提

- Ubuntu 22.04系 + Jetson Linux **JP6.2 (L4T R36.4.x)**
- GStreamer 1.20.x
- NVIDIAエンコーダ要素が利用可能 (`nvv4l2av1enc`)
- ネットワークアクセスあり (Rust crate取得のため)

確認コマンド:

```bash
uname -r
cat /etc/nv_tegra_release
gst-inspect-1.0 --version
gst-inspect-1.0 nvv4l2av1enc
```

## 最短セットアップ

```bash
cd /path/to/nicoryo-rtpav1
./scripts/jp6_2/setup_rtpav1_local.sh --with-apt
source ./scripts/jp6_2/env_rtpav1.sh
gst-inspect-1.0 rtpav1pay
```

## x86 Ubuntuで`rtpav1depay`のみ導入する場合

```bash
cd /path/to/nicoryo-rtpav1
./scripts/x86_ubuntu/setup_rtpav1depay.sh
source ./scripts/x86_ubuntu/env_rtpav1.sh
gst-inspect-1.0 rtpav1depay
```

## x86 Ubuntu検証済みパイプライン

検証環境:
- Ubuntu 22.04 x86_64
- GStreamer 1.20.3
- `rtpav1depay` は `scripts/x86_ubuntu/setup_rtpav1depay.sh` で導入

要素確認:

```bash
source ./scripts/x86_ubuntu/env_rtpav1.sh
gst-inspect-1.0 rtpav1depay
gst-inspect-1.0 av1dec
```

受信再生 (検証済み):

```bash
source ./scripts/x86_ubuntu/env_rtpav1.sh
./scripts/x86_ubuntu/run_rtpav1_receiver.sh --port 5504 --payload 97
```

同等の`gst-launch-1.0`コマンド:

```bash
gst-launch-1.0 -v \
  udpsrc port=5504 caps="application/x-rtp,media=video,encoding-name=AV1,payload=97,clock-rate=90000" ! \
  rtpjitterbuffer latency=100 ! rtpav1depay ! av1parse ! av1dec ! videoconvert ! autovideosink sync=false
```

デコードのみ確認したい場合:

```bash
gst-launch-1.0 -v \
  udpsrc port=5504 caps="application/x-rtp,media=video,encoding-name=AV1,payload=97,clock-rate=90000" ! \
  rtpjitterbuffer latency=100 ! rtpav1depay ! av1parse ! av1dec ! fakesink
```

## `libgstkvssink.so` 警告を抑えるクリーンアップ

以下の警告が出る環境向けの任意対応です:

```text
Failed to load plugin ... libgstkvssink.so: libKinesisVideoProducer.so: cannot open shared object file
```

`kvssink`を使わない場合は無効化できます:

```bash
./scripts/x86_ubuntu/cleanup_gst_warnings.sh
```

戻す場合:

```bash
./scripts/x86_ubuntu/cleanup_gst_warnings.sh --restore
```

`--with-apt` は以下をインストールします (sudo必要):
- `nvidia-l4t-gstreamer`
- `build-essential pkg-config git curl ca-certificates`
- `libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`

APT変更を避ける場合は `--with-apt` なしで実行してください。

## 送受信テスト (別デバイス)

### 受信側 (Device B)

```bash
cd /path/to/nicoryo-rtpav1
source ./scripts/jp6_2/env_rtpav1.sh
./scripts/jp6_2/run_rtpav1_receiver.sh --port 5004 --out /tmp/rx.av1
```

### 送信側 (Device A)

```bash
cd /path/to/nicoryo-rtpav1
source ./scripts/jp6_2/env_rtpav1.sh
./scripts/jp6_2/run_rtpav1_sender.sh --host <RECEIVER_IP> --port 5004 --seconds 30
```

### 受信データ確認

```bash
gst-launch-1.0 -e filesrc location=/tmp/rx.av1 ! av1parse ! av1dec ! fakesink sync=false
```

## ループバック自己診断 (単体)

同一デバイス内で送受信する簡易E2Eテストです。

```bash
cd /path/to/nicoryo-rtpav1
source ./scripts/jp6_2/env_rtpav1.sh
./scripts/jp6_2/selftest_rtpav1_loopback.sh --seconds 20
```

成功時は `/tmp/rtpav1_loopback_rx.av1` が生成され、デコード確認まで行います。

## systemdサービス化 (本リポジトリ実装)

常駐運用する場合は、以下のスクリプトでsystemd登録できます。

```bash
cd /path/to/nicoryo-rtpav1
./scripts/jp6_2/setup_systemd_service.sh install --mode sender --host <RECEIVER_IP> --port 5004
```

デフォルトは `sender` モードかつ `--seconds 0`（無期限送信）です。

状態確認:

```bash
./scripts/jp6_2/setup_systemd_service.sh status
```

受信常駐として登録する場合:

```bash
./scripts/jp6_2/setup_systemd_service.sh install --mode receiver --port 5004 --out /var/tmp/nicoryo-rx.av1
```

削除:

```bash
./scripts/jp6_2/setup_systemd_service.sh uninstall
```

## 運用時の推奨初期値

- 送信:
  - `nvv4l2av1enc bitrate=4000000 iframeinterval=30 idrinterval=30`
  - `rtpav1pay pt=96 mtu=1200`
- 受信:
  - `rtpjitterbuffer latency=100`
  - ロスが多い場合は `latency=150` を検討

## 主要ファイル

- `scripts/jp6_2/setup_rtpav1_local.sh`: ローカル環境セットアップ
- `scripts/jp6_2/env_rtpav1.sh`: 実行時環境変数 (`GST_PLUGIN_PATH`) 設定
- `scripts/jp6_2/run_rtpav1_sender.sh`: RTP/AV1送信
- `scripts/jp6_2/run_rtpav1_receiver.sh`: RTP/AV1受信
- `scripts/jp6_2/selftest_rtpav1_loopback.sh`: ループバック検証
- `scripts/jp6_2/setup_systemd_service.sh`: systemd登録/削除/状態確認
- `scripts/jp6_2/common_jp62.sh`: JP6.2 (L4T R36.4.x) 判定
- `scripts/x86_ubuntu/setup_rtpav1depay.sh`: x86 Ubuntu向け `rtpav1depay` 導入
- `scripts/x86_ubuntu/run_rtpav1_receiver.sh`: x86 Ubuntu向け RTP/AV1受信 (既定デコーダ: `av1dec`)
- `scripts/x86_ubuntu/cleanup_gst_warnings.sh`: `libgstkvssink.so` 警告の任意クリーンアップ

## JP6.2判定について

各スクリプトは `/etc/nv_tegra_release` を読み取り、`R36.4.x` (JP6.2) 以外では停止します。  
検証目的でチェックを無効化したい場合のみ、以下を指定してください。

```bash
SKIP_JP62_CHECK=1 ./scripts/jp6_2/setup_rtpav1_local.sh
```
