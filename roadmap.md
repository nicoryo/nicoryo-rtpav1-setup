# AV1 RTP Enablement Roadmap (Jetson Orin NX)

## 0. 現状サマリ (2026-02-13)
- Device: Jetson Orin NX
- Kernel: `5.15.148-tegra`
- L4T: `R36.4.7` (`nvidia-l4t-core 36.4.7-20250918154033`)
- GStreamer: `1.20.3`
- 現状の不足:
  - `rtpav1pay` が未検出 (GStreamer 1.22+ で追加された要素)

## 実行ステータス
- Phase 1: 完了 (2026-02-13)
  - `nvidia-l4t-gstreamer 36.4.7-20250918154033` 導入済み
  - `nvv4l2h264enc`, `nvv4l2h265enc`, `nvv4l2av1enc` 検出済み
  - `nvvideo4linux2` プラグイン有効化済み
- Phase 2: 完了 (2026-02-13)
  - 実行コマンド:
    - `gst-launch-1.0 -e videotestsrc num-buffers=120 ! video/x-raw,format=I420,width=1280,height=720,framerate=30/1 ! nvvidconv ! video/x-raw(memory:NVMM),format=NV12 ! nvv4l2av1enc bitrate=4000000 ! av1parse ! filesink location=/tmp/phase2_hw_av1_test.av1`
  - 成果物:
    - `/tmp/phase2_hw_av1_test.av1` (約2.1MB) 生成成功
  - ログ上で `NvVideo: NVENC` を確認
  - `filesrc ! av1parse ! av1dec ! fakesink` でEOSまで再生確認
- Phase 3: 完了 (2026-02-13)
  - `videotestsrc` 入力でAV1 ES生成成功:
    - `/tmp/phase3_av1_es_videotest.av1` (約3.8MB)
  - カメラ入力でAV1 ES生成成功:
    - `/dev/video0` -> `/tmp/phase3_cam0_av1_es.av1` (約2.0MB)
    - `/dev/video1` -> `/tmp/phase3_cam1_av1_es.av1` (約2.0MB)
  - 生成ファイルは `filesrc ! av1parse ! av1dec ! fakesink` でEOSまで確認
- Phase 4: 完了 (2026-02-13, ローカルプラグイン方式)
  - 方針: 既存環境保護のため、システムGStreamerは更新せず実施
  - 実施:
    - Rust toolchainをユーザー領域 (`~/.cargo`) に導入
    - `gst-plugins-rs` の `net/rtp` をローカルビルド
    - 生成物: `/tmp/gst-plugins-rs/target/release/libgstrsrtp.so`
    - `GST_PLUGIN_PATH=/tmp/gst-plugins-rs/target/release` で `rtpav1pay` / `rtpav1depay` を有効化
  - E2E検証:
    - 送信: `nvv4l2av1enc ! av1parse ! rtpav1pay ! udpsink`
    - 受信: `udpsrc ! rtpav1depay ! av1parse ! filesink`
    - 出力: `/tmp/p4_rtp_rx.av1` (約129KB)
    - 受信ファイルを `av1parse ! av1dec ! fakesink` でEOS確認
- 残課題:
  - `rtpav1pay` は標準環境には未導入 (現行GStreamer 1.20.3)
  - 本番運用には `GST_PLUGIN_PATH` 設定の恒久化、またはGStreamer 1.22+ への移行が必要
- Phase 5: 完了 (2026-02-13)
  - 検証条件:
    - baseline (30秒): `rtpjitterbuffer latency=100`
    - 疑似ロス (30秒): 送信側 `identity drop-probability=0.03` + `rtpjitterbuffer latency=150`
    - 疑似遅延 (30秒): 送信側 `identity sleep-time=2000` + `rtpjitterbuffer latency=60`
    - 連続動作 (60秒): `rtpjitterbuffer latency=120`
  - 結果:
    - `/tmp/p5_baseline_rx.av1` 生成・デコード成功
    - `/tmp/p5_loss3_rx.av1` 生成・デコード成功
    - `/tmp/p5_delay_rx.av1` 生成・デコード成功
    - `/tmp/p5_60s_rx.av1` 生成・デコード成功
  - 備考:
    - 受信側はUDPのためEOSを受けない。`timeout`で停止し、出力ファイルの復号可否で判定。

## 1. 目標
1. GStreamerでAV1エンコードを使用可能にする  
2. RTPでAV1を送出可能にする  
3. 最終的にAV1ハードウェアエンコード運用を成立させる

## 2. フェーズ別ロードマップ

### Phase 1: NVIDIA GStreamer基盤を有効化
目的: `nvv4l2*` 要素を使える状態にする

作業:
- NVIDIAパッケージ導入
  - `sudo apt update`
  - `sudo apt install -y nvidia-l4t-gstreamer`
- 必要に応じてJetPackメタ導入
  - `sudo apt install -y nvidia-jetpack`

確認:
- `gst-inspect-1.0 | rg -i 'nvv4l2|nvvideo4linux2'`
- 期待結果: `nvv4l2h264enc`, `nvv4l2h265enc` などが見える

完了条件:
- NVIDIA GStreamerプラグインが列挙される

### Phase 2: AV1 HWエンコード可否の単体確認
目的: SoC/ドライバ側でAV1 HW encodeが実際に動くことを確認

作業:
- 優先: Jetson Multimedia APIサンプル `01_video_encode` でAV1出力試験
- 代替: `nvv4l2av1enc` でAV1ビットストリーム生成確認

確認:
- AV1ファイル出力成功
- ログにエラーなし

完了条件:
- AV1ハードウェアエンコードの実機動作が確認できること

### Phase 3: GStreamerでAV1 ESパイプラインを成立
目的: RTP化前に、GStreamer経由のAV1エンコードを安定動作させる

作業:
- 例: `videotestsrc` またはカメラ入力から `nvv4l2av1enc` へ接続
- `av1parse` 経由で `filesink` 出力し再生検証

確認:
- `gst-inspect-1.0 nvv4l2av1enc` が成功
- 出力AV1が再生可能

完了条件:
- GStreamer AV1エンコード(非RTP)で継続動作

### Phase 4: AV1 RTP化
目的: `rtpav1pay`/`rtpav1depay` を使ったRTP送受信を成立

課題:
- 現在のGStreamer `1.20.3` には `rtpav1pay` がない

対応案:
- 案A (推奨): GStreamer 1.22+ に更新し `rtpav1pay` を利用
- 案B (暫定): AV1を別コンテナ化してRTP運搬する暫定構成

確認:
- 送信側: `... ! rtpav1pay ! udpsink ...`
- 受信側: `udpsrc ... ! rtpav1depay ! av1parse ! ...`

完了条件:
- AV1 RTPで送受信・復号が成功

### Phase 5: 実運用チューニング
目的: レイテンシ・安定性・画質の要件を満たす

作業:
- bitrate, iframe間隔, latency, queue設定調整
- ネットワークロス時の復帰確認
- 長時間連続動作試験

完了条件:
- ターゲット条件で安定稼働

## 3. マイルストーン
- M1: `nvv4l2*` 検出完了
- M2: AV1 HW encode単体成功
- M3: GStreamer AV1 ES成功 (完了)
- M4: AV1 RTP成功 (完了: ローカルプラグイン方式)
- M5: 実運用パラメータ確定 (暫定)

## 4. 直近アクション
1. `GST_PLUGIN_PATH` をサービス起動時に設定し、`rsrtp` を運用パスへ固定
2. もしくはGStreamer 1.22+ へ更新し、`rtpav1pay` を標準提供化
3. 実ネットワーク (別ホスト間) でロス/遅延を注入し、`rtpjitterbuffer latency` と `bitrate` の最終値を確定
4. 長時間試験を 60秒から 1時間以上へ拡張

## 5. 暫定推奨パラメータ (現環境)
- 送信側:
  - `nvv4l2av1enc bitrate=4000000 iframeinterval=30 idrinterval=30`
  - `rtpav1pay pt=96 mtu=1200`
- 受信側:
  - `rtpjitterbuffer latency=100` を基準値
  - ロス想定時は `latency=150` まで拡大して安定化を優先
