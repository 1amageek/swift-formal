# swift-formal

Swift・Rust・C・C++・Go・TypeScript・JavaScript・Pythonのスカラー関数を共通IRへ変換し、TLA+とLeanを生成するSwiftパッケージです。CLIの名前は **`formal`** です。

`formal check` は、指定した入力と期待結果について、生成からTLCによるモデル検査、Leanによる証明の確認まで実行します。Java・TLC・Leanは導入時に自動配置されるため、個別の手動インストールは不要です。導入後の生成・検証はオフラインで動作します。

```text
Source code + Scenario
          |
          v
     Common IR
          |
     +----+----+
     v         v
    TLA+      Lean
     |         |
    TLC    Lean kernel
     +----+----+
          v
    Verification report
```

現在は実験的なスカラー言語プロファイルに対応しています。検証対象は**生成モデルの指定された有限ケース**です。元言語からモデルへの一般的な意味保存、任意の入力に対する正しさ、Actor・asyncの意味論は未認証・未対応です。実装状況は [PROGRESS.md](PROGRESS.md) を参照してください。

## 導入

現在の配布対象は **macOS / Apple Silicon（arm64）** です。パッケージの最小macOSバージョンは13、ソースビルドに必要なSwift toolsの最小バージョンは6.2です。動作確認にはSwift 6.4.1を使用しています。

### ソースから導入する

パッケージルートで実行します。ビルドにはSwiftツールチェーンが必要です。

```sh
swift run -c release formal install --prefix "$PWD/InstalledFormal"
./InstalledFormal/bin/formal toolchain
```

`install` が固定バージョンのツールを取得し、指定したprefix内に配置します。

| 同梱ツール | バージョン | 用途 |
|---|---|---|
| Eclipse Temurin JRE | 21.0.13+9 | TLCの実行 |
| TLA+ tools | 1.7.4 | SANYによる構文・意味解析、TLCによるモデル検査 |
| Lean | 4.35.0 | 生成モデルの期待結果を表す定理の確認 |

アーカイブのSHA-256と展開後のファイル一覧を検証します。ダウンロードキャッシュの既定値は `~/Library/Caches/formal/downloads` で、`--cache <directory>` で変更できます。ツール一式は展開後約3 GB、ダウンロードするアーカイブは合計約1 GBです。導入先の同一バージョンと `bin/formal` は未作成である必要があります。

### バイナリ配布フォルダから導入する

配布フォルダを受け取った場合は、次のように導入できます。配布フォルダにはツールが含まれており、この操作にネットワークやSwiftツールチェーンは必要ありません。

```sh
./Formal-macos-arm64/formal install --prefix "$PWD/InstalledFormal"
./InstalledFormal/bin/formal toolchain
```

配布フォルダ内の `formal` を直接実行することもできます。本体・リソース・`toolchain` は同じフォルダに保持してください。詳しくは [配布とインストール](Documentation/DISTRIBUTION.md) を参照してください。

## クイックスタート

導入したprefixと同じ作業ディレクトリに、次の2ファイルを保存します。

`input.py`:

```python
def calculate(a: int, b: int) -> int:
    return a + b
```

`cases.json`:

```json
{
  "schemaVersion": 1,
  "fuel": 512,
  "cases": [
    {
      "name": "addition",
      "entry": "calculate",
      "arguments": ["2", "9"],
      "expected": { "status": "returned", "value": "11" }
    }
  ]
}
```

生成と検証を一度に実行します。

```sh
./InstalledFormal/bin/formal check \
  --language python \
  --source input.py \
  --scenario cases.json \
  --output Checked
```

`Checked` は新規ディレクトリで、親ディレクトリは存在する必要があります。結果は標準出力と `Checked/verification/<run-id>/report.json` に保存されます。TLCの反例、Leanの証明ソース、実行ログも同じrunディレクトリ内に残ります。

### 結果の読み方

| 項目・状態 | 意味 |
|---|---|
| `artifactDataMatchesIR: true` | 実際のTLA+・Lean出力を独立に読み直し、IRとの一致を確認した |
| `tlc: MODEL_CHECKED` | 指定ケースの探索が完了し、期待結果と終端状態への到達を確認した |
| `lean: PROVED` | 指定ケースの期待結果についてLeanが証明を確認した |
| `COUNTEREXAMPLE` / `UNPROVED` | TLCが反例を見つけた、またはLeanで期待結果を証明できなかった |
| `UNKNOWN` | 計算上限、タイムアウトなどにより検証を完了できなかった |
| `translation: UNVALIDATED` | 元言語から生成モデルへの一般的な意味保存は未認証 |

`PROVED` の公理依存は `propext`・`Classical.choice`・`Quot.sound` の許可リストと照合し、実際の依存を `leanAxioms` に記録します。`sorryAx` や独自公理は許可しません。期待値を変更すると、その期待値に対して再検証されます。成功は指定ケースについての結果であり、他の入力へ一般化されません。

### 既存の生成物を再検証する

```sh
./InstalledFormal/bin/formal check \
  --artifact Checked --scenario cases.json --timeout 120
```

実行ごとに新しいrunディレクトリを作ります。`--timeout` は各外部プロセスの制限時間で、既定値は120秒です。シナリオは最大32ケース、`fuel` は1〜4096です。引数と期待値は文字列で指定します。戻り値のほか、`trapped`・`panic`・`undefinedBehavior` の期待も記述できます。スキーマと資源上限の詳細は [シナリオ仕様](Documentation/DISTRIBUTION.md#generate-and-check) を参照してください。

## 対応言語と範囲

| 言語 | `--language` | 主な型・前提 |
|---|---|---|
| Swift | `swift` | `Int64`・`UInt64`・`Bool`、引数ラベルなし |
| Rust | `rust` | `i64`・`u64`・`bool`、Rust 2021、オーバーフロー検査有効 |
| C | `c` | `int64_t`・`uint64_t`・`bool`、標準ヘッダー、C11 |
| C++ | `cpp` | `int64_t`・`uint64_t`・`bool`、標準ヘッダー、C++20 |
| Go | `go` | `int64`・`uint64`・`bool`、package宣言が必要 |
| TypeScript | `typescript` | プリミティブな `bigint`・`boolean` |
| JavaScript | `javascript` | 引数・戻り値にプリミティブなBigIntを仮定 |
| Python | `python` | 組み込みの `int`・`bool`、型注釈が必要 |

対応するのは独立した純粋関数、変更しないローカル変数、整数演算・比較、直接呼び出し、両分岐でreturnする条件分岐などです。整数の幅やオーバーフローの扱いは言語ごとに区別します。Pythonの `int` とJS/TSのBigIntは任意精度整数として扱います。

一般のプロジェクト、クラス・オブジェクト、可変状態・メモリ操作、例外、Actor・async、JS/TSのNumberや暗黙の型変換は現在のソースプロファイルの対象外です。未対応の構文はソース位置付きの診断で拒否します。正確な文法と前提は [Frontend契約](Sources/FormalCompiler/Frontends/DESIGN.md) を参照してください。

```sh
./InstalledFormal/bin/formal profiles
```

## 生成のみ実行する

```sh
./InstalledFormal/bin/formal translate \
  --language rust \
  --source Fixtures/Sources/rust.source \
  --output DraftRust \
  --draft-unvalidated
```

`--draft-unvalidated` は必須で、最後に指定します。`translate` は外部検証ツールを実行せず、`DRAFT_UNVALIDATED` として出力します。

```text
Checked/
├── source.txt
├── program.json
├── report.json                 Generation report
├── tla/                        TLA+ program and runtime
├── lean/                       Lean program and runtime
└── verification/<run-id>/       Created by check
    ├── report.json              Verification report
    ├── lean/                   Controlled proof source
    └── case-0/                 TLC / Lean logs and trace
```

## 配布物を作る

```sh
swift run -c release formal package --output "$PWD/Formal-macos-arm64"
```

本体・リソース・検証ツール・ライセンスを含む移動可能なフォルダを作ります。配布はフォルダ全体で行います。このコマンドはローカルの配布物を作成し、公開・署名・notarizationは行いません。

## パッケージ構成

外部SwiftPM依存はありません。検証用のJava・TLC・LeanはCLIの導入・配布物作成時に管理します。

```text
formal ──► FormalCompiler ──► FormalIR ──► FormalCore
       ├─► FormalValidation ────┘             ▲
       └─────────────────────────────────────┘
```

| モジュール | 責務 |
|---|---|
| `FormalCore` | 共通メタデータ、診断、入力バンドルの整合性確認 |
| `FormalIR` | 言語共通の型付きIRと実行意味論 |
| `FormalCompiler` | 言語別Frontend、SIL処理、TLA+・Lean出力 |
| `FormalValidation` | 独立した出力解析、ツール管理、有限ケースの検証 |
| `formal` | CLI、生成・検証・配布の組み立て |

SILの構造解析と一部のスカラーloweringもライブラリとして提供します。`capture`・`generate`・`validate`・`coverage`・`replay` は現在未実装で、終了コード3を返します。

## 開発と検証

```sh
swift build
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
```

実際のTLC・Lean、配布物の移動、ホストツールを遮断した実行、元言語との比較などの検証手順と確認済み範囲は [検証記録](Documentation/VERIFICATION.md) にあります。

## ドキュメント

- [CLIと終了コード](Documentation/CLI.md)
- [配布・導入・シナリオ仕様](Documentation/DISTRIBUTION.md)
- [対応範囲](Documentation/SUPPORT.md)
- [設計](DESIGN.md)
- [信頼境界](Documentation/TRUST.md)
- [実装状況](PROGRESS.md)
- [当初仕様のスナップショット](Documentation/SPEC.md)
