# swift-formal — SILからTLA+ / Leanを自動生成するための実装仕様

- 仕様バージョン: 0.1
- 作成日: 2026-11-16
- 状態: 実装担当エージェントへの引き継ぎ用仕様。実装・実行・検証完了の報告ではない。
- パッケージ名 / CLI名: `swift-formal`
- 独立したSwift Package / リポジトリとして作成する。
- 既存の`swift-skeleton`は変更せず、ライブラリ依存として利用する。

本文のMUSTは必須、SHOULDは原則必須で例外の理由を記録するもの、MAYは任意の拡張を示す。API・コマンド・ファイル構成は本パッケージで新設する契約であり、現在利用できる既存コマンドの説明ではない。

## 1. 決定事項と目的

`swift-formal`は、Swift Intermediate Language（SIL）で表されたプログラムの実行意味を、決定論的な変換によってTLA+とLeanへ出力する形式化コンパイラである。

必須機能は次の2つとする。

1. **SIL → TLA+の完全自動生成。**
2. **SIL → Leanの完全自動生成。**

この2つは別々の実装を独自解釈で生成するのではなく、同じ入力SILと、同じ意味を定義した共通中間表現FormalIRから生成する。

利用者は生成されたTLA+・Leanを手書き・修正しなくてよい。入力コードの意味をAIや人間が読み替えてモデル化する工程を、生成パイプラインに置かない。

SILからの形式化を本体とし、SwiftPMからのSIL採取、宣言索引、モデル検査・証明実行、結果表示は周辺機能とする。

## 2. 「完全自動」の定義

### 2.1 自動化の契約

対応するツールチェーン・意味モデル・SILプロファイル内で、次を無人で完了しなければならない。

- SILの構文解析、整合性検査、必要な依存先の解決。
- 型、制御フロー、データフロー、メモリ、例外、並行処理の意味をFormalIRへ変換。
- TLA+およびLeanの出力。
- 出力の構文検査・型検査と、変換対応の検査。
- 入出力、使用した意味モデル、適用規則、診断を含む追跡可能なレポートの出力。

禁止事項:

- 実行時のLLM呼び出し、自然言語によるモデル補完。
- 関数名やコメントを見て実装の意味を推測すること。
- 利用者に生成後の`.tla`や`.lean`の編集を要求すること。
- 未対応命令を削除、no-op化、任意値化して成功すること。
- 未知の外部呼び出しを「副作用なし」と仮定すること。
- 証明できない命題を`axiom`や`sorry`で成立させること。

実装エージェントが変換器のコードを書くことは問題ない。生成物の正当性を、そのエージェントの解釈や自己申告に依存させないことが要件である。

### 2.2 生成と検証を分離する

次の状態は同一ではない。

- TLA+ / Leanを生成できた。
- SILと生成物の意味的対応が検査された。
- 有限シナリオで反例が見つからなかった。
- 指定した命題の証明がLeanで検査された。

完全自動生成は、任意のプログラムの停止性や任意の業務要件を自動証明する約束ではない。生成対象には非停止プログラムも含められるようにする。

業務上の不変条件・入力の範囲・外界の応答はSILから一意に決まらない場合がある。これらは実装の再記述ではなく、別の検査入力として扱う。生成自体には業務仕様の入力を必須としない。

### 2.3 対応範囲

最終目標は対応するSwiftツールチェーンのSILへ広く対応することである。開発段階の対応範囲はバージョン付きプロファイルで公開する。

「完全自動」は手動工程の有無を表し、「すべてのSIL命令・全ランタイム・任意の外部サービスに既に対応済み」という意味ではない。未対応入力は明示的に拒否する。プロファイルを限定しているリリースは、制限を隠して汎用完全対応と宣伝しない。

## 3. 既存swift-skeletonの利用境界

確認した参照コミット:

`1amageek/swift-skeleton@fb10ef666a30e892b9f3a4ca0740702c6c621d80`

既存パッケージは宣言・ソース位置・実装の特徴を索引するものであり、型解決、実装意味の証明、完全な呼び出し解決を行わない。関数本文を索引の意味表現として保持する設計でもない。[R1]

利用する公開product:

| Product | swift-formalでの用途 |
|---|---|
| `SkeletonIndexCore` | 宣言索引、検索、ソース位置の表示 |
| `SkeletonSwiftParser` | Swift宣言・Actor・メソッドの発見 |
| `SkeletonSwiftPMProjectSupport` | パッケージ・ターゲット構成の補助情報 |

`SkeletonIndexClient`は将来のUI統合に利用してもよいが、生成エンジンの必須依存にしない。

重要な境界:

- SILを実行意味の入力とする。Skeletonの出力を意味復元に使わない。
- `[impl:*]`などのheuristicを変換の根拠にしない。
- Skeletonの公開API表示用フィルターで、検証に必要なprivate関数や依存実装を除外しない。
- 実際のビルド引数、条件付きコンパイル、マクロ展開、外部依存の取得はコンパイラ／ビルド層が担当する。
- 索引で宣言が見つからなくても、SILからの変換は可能でなければならない。対応するSwiftソース位置が不明という診断を出す。
- SILだけが与えられたモードでは、Swiftソースを必須としない。
- シンボル同一性はmangled symbolとモジュールで扱う。行番号や同名の関数だけで同一視しない。

依存はコミットまたはリリースを固定する。`main`の追従をリリースの既定値にしない。

参照したPackage.swiftはSwift tools version 6.2、macOS 13を指定している。[R2] 本パッケージの初期ホスト対象もこれを最低条件とし、実際に動作保証するSwiftコンパイラとターゲットは`toolchain.lock.json`で厳密に固定する。「6.2以上なら任意のSIL形式を受理する」という意味ではない。

## 4. 全体構成

```text
Swift Package ── Capture / Build adapter ── SIL bundle ────────────┐
                                                               │
既存のSIL + build context ────────────────────────────────────────┤
                                                               ▼
                                        SIL parser / verifier / linker
                                                               │
                                        Typed SIL representation
                                                               │
                                     checked lowering + certificates
                                                               ▼
                                              FormalIR
                                              │      │
                                      TLA emitter   Lean emitter
                                              │      │
                                              ▼      ▼
                                             TLA+   Lean
                                              │      │
                                     output / translation validation
                                              │      │
                                     TLC (optional)  Lean proof check
                                              └──┬───┘
                                                 ▼
                                  manifest / coverage / diagnostics / report

swift-skeleton ── 宣言索引・ソース位置 ── SourceMap / UI
                 （実行意味の入力とは分離）
```

Swift→SILのコンパイラも、SIL→形式表現の変換器も無条件に正しいと宣言しない。保証の直接の対象は、記録されたSIL入力と、選択された実行意味・ランタイムモデルである。

## 5. 入力仕様

### 5.1 SIL直接入力

必須入力:

- 1個以上の`.sil`ファイル、またはSIL bundle。
- ツールチェーン識別子とバージョン。
- ターゲットトリプル、データレイアウト、Swift言語モード。
- SIL段階、ownershipなどの形式情報。
- 標準ライブラリ・ランタイム・外部モジュールの識別情報。
- 対象エントリーポイントまたは対象モジュール。

不足情報をホスト環境から推測して続行しない。例えば`Int`の幅をホストマシンの幅で決めない。

初期対応は、固定ツールチェーンの**canonical SIL / -Onone取得構成**とする。raw SILはそのまま同一仕様として受け付けない。将来対応する場合は、正規化経路と検査を別に定義する。

Swiftの公式資料では、raw SILと、必須の変換・診断を通過したcanonical SILを区別している。[R3][R4] 本仕様のcanonical指定は、性能最適化済みであるという意味ではない。

### 5.2 SwiftPMからのSIL採取

`capture`は次を行う。

1. SwiftPMの対象ターゲットと実際のビルド構成を解決する。
2. 必要なマクロ、生成ソース、依存モジュールを通常のビルド条件に従って処理する。
3. 対応コンパイラを用いてSILを取得する。
4. コマンドライン、compiler flags、SDK、依存解決、ソース・モジュールのハッシュを保存する。
5. 直接入力と同じbundleへ正規化する。

`swift-skeleton`のターゲット情報だけを完全なbuild planと見なしてはならない。

Debug構成のSILを検証した結果を、異なるRelease構成のバイナリへそのまま適用しない。生成時の構成と結果の対象を明示する。

### 5.3 SIL bundle

```text
Input.silbundle/
├── manifest.json
├── modules/
│   ├── Main.sil
│   └── Dependency.sil
├── build-context.json
├── toolchain.lock.json
└── source-map.json       # ソースがある場合
```

manifestには入力ファイルの順序、ハッシュ、エントリーポイント、依存閉包、標準ライブラリ／ランタイムモデル、プロファイル、除外範囲を記録する。

## 6. SILフロントエンド

### 6.1 パーサ

- バージョン付き文法に基づくパーサを実装する。正規表現による命令の抜粋だけでは実装完了としない。
- 複数行命令、型、属性、generic substitutions、basic block引数、debug locationを構造化する。
- 未知の命令、未知の意味を持つ属性、未知の型形式を検出する。
- 未知の部分を単に文字列で保持して「対応済み」としてはならない。
- 対応コンパイラのSIL verifierが利用できる場合、入力検査にも使用する。利用する補助実行ファイルとバージョンをlockする。

パース成功と意味対応は別の状態として記録する。

### 6.2 依存閉包・呼び出し解決

対象エントリーポイントから、参照される関数、global initializer、デストラクタ、closure、必要なdispatch tableや型情報を含める。

外部関数の意味を得る方法は次のいずれかに限定する。

| 方法 | 扱い |
|---|---|
| 本体のSILがある | 同じパイプラインで変換 |
| バージョン管理された組み込み意味モデルがある | 適用条件・実装対応・信頼境界を記録して使用 |
| 明示的な環境契約が指定されている | その契約を前提とする条件付きモデルとして生成 |
| いずれもない | `UNSUPPORTED_EXTERNAL`で生成失敗 |

型・module・完全なsymbol・runtime version等の一致を確認する。demangled名の部分一致だけで標準ライブラリの意味モデルを適用しない。

動的dispatchの候補を一意に解決できないこと自体は直ちに誤りではない。対応するruntime型・tableの意味を表現できるなら保持する。表現できない候補を黙って落とすことは禁止する。

有限に特殊化できるgenericsだけに対応する段階では、その制限をプロファイルへ記録する。無限に特殊化し得るケースで処理を無限に続けず、資源制限を診断する。

### 6.3 対象外処理

明示された依存閉包外のシンボルは生成対象外とできる。ただし除外理由を記録する。

閉包内の命令を削除する場合は、意味を持たないdebug metadataであるか、到達不能性・変換保存の検査が必要である。「テストで通らなかった」「AIが不要と判断した」は根拠にならない。

## 7. FormalIR

### 7.1 目的

FormalIRは、SILの意味をTLA+ / Leanで共有するための、型付きで明示的な状態遷移表現である。高水準のSwiftコードを推測して復元する層ではない。

初期版では最適化や大胆な抽象化を行わず、SILからの対応を追跡しやすい命令単位の変換を優先する。

### 7.2 静的構造

| 要素 | 必須情報 |
|---|---|
| Module | module ID、依存、globals、functions、型定義 |
| Function | symbol、型、引数・結果のconvention、async/isolation、CFG |
| Block | block ID、SSA block arguments、命令列、terminator |
| Instruction | opcode、typed operands、結果、属性、意味規則ID |
| Type | bit width、signedness、aggregate、enum payload、address/reference等 |
| SourceOrigin | SILファイル・位置、Swift位置があれば併記 |

### 7.3 実行状態

対応プロファイルに必要な次の情報を保持する。

- task、call frame、program counter、SSA value environment。
- globals、stack storage、heap object、object identity、address projections。
- 所有権・参照の状態。観測可能な破棄やweak参照を省略しない。
- actor、executor、その所有task、runnable / suspended状態、continuation。
- 正常終了、throw、trap、未定義動作の検出状態。
- 検証用上限を使用した場合の`BOUND_EXCEEDED`。

call stackや動的メモリを数学的に無制限に表現できる設計とし、TLCのための有限化は別層で行う。

### 7.4 実行意味

小ステップ意味論を基本とする。

```text
Step(program, state, event, nextState)
```

各opcodeについて、引数型、前提、状態変更、失敗、観測イベントを明記する。

観測対象にはreturn値、可視のメモリ更新、throw / trap、I/O契約上のイベント、必要な並行イベントを含める。どの内部操作をstutteringとして扱えるかは規則で定義する。

命令が同じCFG block内にあることは、そのblock全体が他taskから見て不可分であることの根拠にならない。

## 8. 意味保存に関する必須規則

### 8.1 整数

固定幅整数はbit widthとsignednessを保持する。TLA+の数学的整数やLeanの`Nat`へそのまま置き換えない。

通常演算のoverflow / trap、wrapping演算、overflow flagを返すbuiltin、signed / unsigned comparison、除算の端点、shift規則を区別する。

TLA+では範囲と演算規則を持つ表現、Leanでは`BitVec`または同等の検査された固定幅モデルを使う。

### 8.2 メモリ・所有権

load/store、inout、alias、stack lifetime、copy/take、aggregate projection、参照同一性を保持する。

ARC関連命令を一律に削除してはならない。削除できるのは、例えばtrivialな値など、選択した観測意味に対して影響しないことが検査された場合だけである。

メモリのdata raceやunsafe pointerを意味定義できないプロファイルでは、対応済みとして扱わない。初期並行プロファイルはdata-race-freeなactor隔離領域を対象とする。弱いメモリ順序を逐次一貫性へ無断で置き換えない。

### 8.3 例外・異常終了

`return`、`throw`、trap、到達不能・未定義動作を区別する。

外部からの前提条件と、本体内で実行されるチェックを区別する。本体のassert / preconditionが失敗する経路を、入力の仮定へ変換して消してはならない。

未定義動作の前提違反は検査対象のエラー状態として扱い、その後の通常動作を保証しない。未定義動作を一般のSwift例外へ置き換えない。

### 8.4 非同期・Actor

SILの非同期関数は`@async`型を持ち、通常の`apply` / `try_apply`等で呼ばれる場合がある。`hop_to_executor`もexecutorの一致状態によって振る舞いが変わる。[R5][R6]

したがって、次をMUSTとする。

- 非同期性はopcode名だけでなく、calleeの型・呼び出しconvention・isolationから決定する。
- `hop_to_executor`を無条件の中断や無条件のno-opにしない。
- callerのlocals、suspend / resume、executorの移動、再入を保持する。
- 同一actorの別taskが中断のない隔離区間の途中へ入るモデルを作らない。
- 別actorや非隔離taskの進行まで同一actorと一緒にロックしない。
- 同期calleeに入っただけでactorのexecutor所有を解放しない。
- task生成・join・continuation・cancellationのうち、対応したAPIをruntimeモデルで列挙する。
- cancellation requestを即時の強制停止として扱わない。
- FIFO実行、fairness、時間内完了を暗黙に仮定しない。
- actorメソッド全体を一つの不可分遷移にしない。

初期版は標準executorに限定してよい。custom executorや未定義のruntime挙動は拒否する。

## 9. TLA+バックエンド

### 9.1 生成物

```text
tla/
├── Program.tla
├── SwiftFormalRuntime.tla
├── Properties.tla
└── scenarios/
    ├── <scenario>.cfg
    └── <scenario>.tla
```

- `Program.tla`: FormalIRで表されたプログラム、初期状態、遷移関係。
- `SwiftFormalRuntime.tla`: 型・演算・frame・memory・schedulerの意味。
- `Properties.tla`: 共通の型整合性や指定された性質。
- scenario: 入力、初期状態、外界、有限化を具体化した検査設定。

scenario未指定でもパラメトリックなTLA+生成を完了できなければならない。具体的な初期状態や入力がない状態で、意味のあるTLC検査をしたことにはしない。

### 9.2 生成する仕様

`Init`、`Next`、状態変数、terminal状態、エラー状態、source mappingを機械的に生成する。

仕様は概念的に`Init /\ [][Next]_vars`を基本とする。fairnessはscenarioの明示入力であり、生成器が勝手に加えない。

正常終了・throw・trapを適切にterminalとして識別し、正常終了をdeadlockと誤判定しない。一方で、全状態に無条件の自己ループを追加してdeadlockを隠すことは禁止する。必要なら、実ステップのenablednessと非terminal状態からdeadlock predicateを生成する。

更新しない状態成分も明示的に保持する。更新忘れによってTLA+の次状態が意図せず自由にならないようにする。

### 9.3 有限化

TLC実行には有限の入力集合やresource boundsが必要になる場合がある。`.cfg`は定数・不変条件などの検査設定を扱う。[R9]

次を区別する。

1. 入力・初期状態・外界を限定した**シナリオの範囲**。
2. 探索の都合で設定したheap・stack・task等の**人工的な上限**。

人工的な上限に到達したら`BOUND_EXCEEDED`として報告する。状態制約でその先を黙って切り落とし、「検証成功」にしない。

入力整数を少数に限定することと、整数演算そのもののbit widthを小さくすることは別である。後者を無断で行わない。

探索完了・未完了、適用上限、fairness、環境契約、state/action constraints、使用した抽象化を結果に記録する。

シナリオの`Init`が少なくとも1つの状態を持つことを検査する。初期状態が空、または仮定が矛盾している場合、vacuousな成功を返さず`INVALID_SCENARIO`とする。充足可能性が未確認なら`UNKNOWN`とする。検査対象の呼び出し自体を初期条件から消して成功させない。

初期版は正確なシナリオ意味を優先する。over-approximationは将来拡張として分離し、健全性証明がある場合だけ使用する。過大近似の反例は実SILで再現できるまで`POTENTIAL_COUNTEREXAMPLE`とする。livenessはsafetyと同じ抽象化根拠で保証しない。

## 10. Leanバックエンド

### 10.1 生成方針

正本となる出力は、プログラムをデータとして表し、その実行規則を形式化するdeep embeddingとする。

- プログラム／命令列／型／関数／状態をLeanの定義へ生成する。
- 共通ランタイム上の`Step`関係を適用する。
- 到達可能性、正常終了、異常終了を定義する。
- 並行処理も同じ状態遷移系としてLeanへ出力する。

TLA+は並行処理のみ、Leanは純粋関数のみ、という機能分断は行わない。対応プロファイル内では両方の出力が同じプログラムを表す。

### 10.2 ループ・再帰

任意のループをLeanの停止する直接再帰関数へ無理に変換しない。Leanの再帰定義には論理の健全性のための条件がある。[R7]

基本は一歩の遷移関係とその有限到達関係で表す。実行用のfuel付き評価器を設ける場合、fuel切れは`OutOfFuel`であり、成功・正常終了・非停止の証明ではない。

非停止動作を扱うため、無限の実行列を述語として表現できる設計にする。停止性を証明しないことを理由にモデル生成を拒否しない。

読みやすい純粋関数形式の出力は追加ビューとしてMAY。正本の状態遷移モデルとの等価性が検査される場合に限る。

### 10.3 生成物

```text
lean/
├── lean-toolchain
├── lakefile.toml
├── SwiftFormal/
│   ├── SILSemantics.lean
│   ├── IRSemantics.lean
│   ├── Runtime.lean
│   └── TranslationRules.lean
├── Generated/
│   ├── InputProgram.lean
│   ├── Program.lean
│   ├── Properties.lean
│   └── TranslationCertificates.lean
└── Verified/
    └── <proved-property>.lean
```

`Properties.lean`では未証明の性質を`def ... : Prop`等で定義できる。証明がないのに`theorem ... := by sorry`を生成してはならない。

自動証明ができなかった性質は`UNPROVED`としてレポートする。モデル生成成功は取り消す必要はないが、アプリケーションの性質が証明済みであるとは表示しない。

### 10.4 証明の監査

- `sorry` / `admit` / `sorryAx`の推移的依存を禁止する。
- 未承認のcustom axiomを禁止する。
- `propext`、`Classical.choice`、`Quot.sound`等、許容する標準公理をlockされたallowlistとして管理する。
- strictモードで、native evaluation等により信頼基盤を拡張する証明方式を無断で使用しない。
- 証明と定理の内容、前提、依存公理を記録する。
- 信頼されたプロセスでカーネルの再検査を行い、単なる出力文字列や生成器自身の成功報告を信頼しない。

Leanの公式資料も、証明の成立と命題の意味を区別し、依存公理の監査を説明している。[R8]

## 11. 変換器の信頼性

### 11.1 必須方針

「決定論的な変換だから正しい」「両バックエンドの結果が一致したから正しい」とはしない。

共有FormalIRのバグは両方の出力へ伝播する。そのため以下の対応を別々に検査する。

- 入力SIL → 型付きSIL表現。
- 型付きSIL表現 → FormalIR。
- FormalIR → Leanプログラム表現。
- FormalIR → 生成TLA+の限定構文と遷移関係。

### 11.2 採用する方式

初期の保証経路は**translation validation + 検査可能な証明証跡**とする。

1. 元の入力artifactを固定し、独立した検査側が入力を読み取る。
2. 生成器が適用規則、symbol対応、型対応、状態対応、命令対応を証跡として出力する。
3. reference semanticsと、検査済みの命令ごとの変換規則から対応を検査する。
4. 出力された実際の`.tla` / `.lean`が対象artifactであることを検査する。
5. 検査結果とartifact hashを結び付ける。

対応表やハッシュの一致だけでは意味保存の証明としない。

Swiftの生成器とは分離したLean側のreference semantics / checkerを設ける。生成器のlowering実装そのものを、独立な検査器の代わりに再実行しない。

### 11.3 証明する関係

対応する状態間で、初期状態、遷移、観測結果、terminal / errorの対応を示す。

正確な変換として表示する場合は、内部のstutteringを適切に扱った双方向の対応、または同等のトレース同値性を要求する。

safetyのための片方向simulationしかない場合は、正確な等価変換と表示しない。過大近似と、その根拠を区別する。

livenessを保証する場合は、進行・発散・fairnessに関する追加条件が必要であり、有限ステップの対応だけで十分としない。

### 11.4 TLA+出力の対応検査

SANYによる構文・意味解析、TLCによる探索だけでは、SILとの対応は証明されない。

初期版で生成するTLA+を限定された構文・テンプレート集合に制限する。その集合について意味を定義し、出力を再解析してFormalIRとの対応を検査する。

再解析結果は型だけでなく、条件、更新式、frame condition、schedulerのenablednessまで対象にする。生成前の内部ASTだけを検査して、実際の出力ファイルの検査を省略しない。

### 11.5 信頼基盤と保証範囲

次は明示的に管理するTrusted Computing Base / assumptionsである。

- Swiftソースと入力SILの関係を担うコンパイラ。
- SILの構文・意味定義と、独立検査側の入力decoder。
- Lean kernelと承認された論理基盤。
- 対象ツールチェーンに結び付いたruntime / stdlibモデル。
- TLA+の限定構文の意味とdecoder、TLCを使う場合はその実行系。
- 未検証の外部サービス契約、OS・ハードウェアなどの環境前提。

変換の検査を行っても、モデル化したSwift runtimeと実環境の一致まで自動的に証明したことにはならない。

### 11.6 リリースの成功条件

strictが既定値。変換対応の検査に失敗した場合、`generate`は成功を返さない。

開発中の未検査生成物を保存するMAYオプションを設ける場合、成果物は`DRAFT_UNVALIDATED`専用ディレクトリへ保存し、認証済み生成物と混同できないようにする。製品の完全自動生成の完了条件には含めない。

## 12. 対応プロファイルとv1の対象

### 12.1 Coreプロファイル

両バックエンドで必須:

- Boolと固定幅整数、tuple、struct、payload付きenum、Optional。
- SSA値、basic block引数、条件分岐、switch、ループ。
- 直接関数呼び出し、return、再帰。
- stack上のload/store、inout、projection、必要なaccess区間。
- 型とbodyが解決可能な具体化generic呼び出し。
- throw/catchに対応する正常・異常の制御経路。
- overflow、division端点、trap、assertion失敗のモデル化。

### 12.2 Actorプロファイル

v1の受け入れ範囲として両バックエンドで必須:

- 単純なactorインスタンスとその保存状態。
- 同期・非同期actorメソッド。
- 標準executorの所有・移動・suspend / resume。
- 固定シナリオの複数taskによる同一actorへの呼び出し。
- fixtureで必要となるclosure、capture、強参照、初期化・破棄の意味。
- 必要なtask / continuation APIの限定されたruntimeモデル。

対応命令名だけでなく、対象runtime APIと利用条件を一覧化する。ActorのSILが読めても、その実行に必要なruntime呼び出しを解決できない場合は未完成である。

### 12.3 初期の非対応候補

未実装なら明示拒否するもの:

- ObjC/C/C++ FFI、Foundation等の未モデル化API。
- unsafe pointer、inline assembly、未モデル化atomic操作。
- custom executor、distributed actor、任意の外部I/O。
- 汎用reflection、未解決のexistential/dynamic dispatch。
- 意味を定義していないfloating point、SIMD、文字列／collection API。
- 未対応のownership/weak参照/deinitの複雑な振る舞い。

これらは永久の非目標ではない。対応追加は意味定義・両バックエンド・検査・回帰テストを一組として行う。

### 12.4 機械可読な対応表

`support-matrix.json`に次を記録する。

- toolchain profile。
- opcode / attribute / builtin / runtime symbol。
- 型・ownership・isolation等の対応条件。
- SIL parser / IR lowering / TLA / Lean / validatorそれぞれの対応状態。
- reference semantics、変換規則、テストの識別子。

プロファイル内のSILで、意味に影響するノードが1つでも未対応なら成功にしない。

## 13. 性質・シナリオの入力

### 13.1 自動で取り出せる検査対象

入力SILに残っているtrap、overflow check、assertion相当の失敗、型整合性、対応モデル上のmemory前提、非terminal deadlock等を扱う。

release最適化などでSILから消えたassertを、SILだけから復元したと主張しない。

### 13.2 ユーザーが指定するもの

業務上の不変条件、望ましい完了条件、初期入力、外界応答、fairnessなど。

JSONの型付き式ASTまたは専用の機械可読形式を用いる。初期版で自然言語仕様を入力形式としない。TLA+ / Leanの手書きコードも必須としない。

利用者が指定する式は実装の代替モデルではなく、検査する性質・環境前提である。仮定は`assumptions`、確認対象は`properties`で分離する。確認対象を暗黙に仮定へ移すことを禁止する。

## 14. CLI契約

以下は実装後の公開CLI契約である。

```bash
# ツールチェーンと環境の診断
swift-formal doctor

# SwiftPMから実際のbuild contextを伴うSILを取得
swift-formal capture \
  --package ./MyPackage \
  --target Inventory \
  --toolchain-lock ./toolchain.lock.json \
  --out ./Input.silbundle

# 2形式を同じ入力から生成（既定値は両方、strict）
swift-formal generate \
  --bundle ./Input.silbundle \
  --emit tla,lean \
  --out ./Generated

# 既存のSILを直接指定
swift-formal generate \
  --sil ./Inventory.sil \
  --context ./build-context.json \
  --emit tla,lean \
  --out ./Generated

# 構文・型・変換対応を再検査
swift-formal validate ./Generated

# scenarioとpropertiesを指定してモデル検査・証明を実行
swift-formal check ./Generated \
  --scenario ./two-reservations.json \
  --properties ./properties.json

# 対応範囲と未対応要素を調べる
swift-formal coverage --bundle ./Input.silbundle

# 反例を元のSILで再生し、対応するSwift位置を表示
swift-formal replay ./Generated --trace ./counterexample.json
```

`--emit tla`、`--emit lean`もサポートする。片方の出力要求でも、内部の意味保存検査にLeanのcheckerを使用してよい。

`generate`は完全なTLC状態探索や業務性質の自動証明を必須にしない。構文・型・変換対応の検査はMUST。

### 終了コード

| Code | 意味 |
|---|---|
| 0 | 要求された操作が、その契約どおり完了 |
| 2 | 引数、manifest、toolchainの不整合 |
| 3 | 未対応構文・命令・型・外部依存 |
| 4 | パース、IR整合性、出力、変換対応の不一致 |
| 5 | 実際の反例を検出 |
| 6 | timeout、上限到達、未証明、その他の未完了 |
| 7 | 内部エラー、外部検査ツールの実行失敗 |

`generate`の0はアプリの性質の証明成功を意味しない。`check`の0でも、`MODEL_CHECKED`か`PROVED`かをJSONで必ず区別する。CIでは許容する結果・scope・assumptionsをpolicyで指定できるようにする。

## 15. 出力とレポート

```text
Generated/
├── manifest.json
├── formal-ir.json
├── semantic-coverage.json
├── source-map.json
├── traceability.json
├── assumptions.json
├── diagnostics.json
├── translation-validation.json
├── report.json
├── tla/
└── lean/
```

### 15.1 3軸の状態

| 軸 | 値の例 |
|---|---|
| generation | GENERATED / UNSUPPORTED / FAILED / DRAFT_UNVALIDATED |
| translation | VALIDATED / UNVALIDATED / MISMATCH |
| property verification | NOT_REQUESTED / MODEL_CHECKED / PROVED / COUNTEREXAMPLE / UNKNOWN / UNPROVED |

`PROVED`には対象定理、前提、依存公理、scopeを付ける。`MODEL_CHECKED`には検査した有限シナリオ、探索完了、上限、使用したモデルを付ける。

### 15.2 記録必須のprovenance

- 入力SIL、対象ソース、依存モジュールのハッシュ。
- compiler、stdlib、SDK、target、build flags、Swift言語モード。
- `swift-formal`、`swift-skeleton`、TLC、Lean、validatorのバージョン。
- FormalIR schema、semantics library、runtime model、support profileのバージョン。
- artifact hash、性質のhash、scenarioのhash。
- 変換範囲、除外範囲、assumptions、coverage。

同一入力・lock・設定から、生成物はbyte-identicalであること。時刻、実行時間、絶対作業パス等の実行メタデータは決定論的なartifactから分離する。

生成は一時ディレクトリで行い、全検査後にatomicに公開する。失敗時に古い成果物を今回の成功結果として返さない。

### 15.3 実行時の安全性

- compiler、Java/TLC、Lean等のsubprocessにはtimeoutと資源制限を設ける。
- 引数配列を使い、入力値をshellの文字列へ連結しない。
- 生成物のimportと利用可能なsemantics libraryを固定する。外部から渡されたLeanコードを無制限に信頼プロセスで実行しない。
- カーネル検査を迂回する設定・コマンドを拒否し、checkerの起動設定もprovenanceへ記録する。
- SwiftPM manifest、build plugin、macroの実行は実際のコード実行を伴う境界として分離し、sandboxまたは信頼済みプロジェクトの条件を設ける。
- 生成はオフラインで可能とする。依存取得・toolchain導入は準備工程として明示し、生成中に外部モデルや新しい依存を無断取得しない。

## 16. パッケージ構成

```text
swift-formal/
├── Package.swift
├── Sources/
│   ├── FormalCore/              # IDs / config / diagnostics / manifest
│   ├── FormalIndex/             # swift-skeleton adapter
│   ├── FormalCapture/           # SwiftPM / compiler integration
│   ├── FormalSIL/               # grammar / typed SIL / verifier adapter
│   ├── FormalIR/                # common state-transition representation
│   ├── FormalLowering/          # SIL -> IR, evidence production
│   ├── FormalTLA/               # TLA AST / emitter
│   ├── FormalLean/              # Lean emitter
│   ├── FormalValidation/        # independent checker orchestration
│   ├── FormalVerification/      # SANY / TLC / Lean runners
│   └── swift-formal/            # CLI
├── Semantics/
│   ├── Lean/                    # reference semantics / translation proofs
│   ├── TLA/                     # generated-runtime templates
│   └── Profiles/                # versioned toolchain/runtime support
├── Tests/
├── Fixtures/
├── Documentation/
│   ├── SEMANTICS.md
│   ├── TRUST.md
│   ├── SUPPORT.md
│   └── CLI.md
└── toolchain.lock.json
```

依存方向はCore → 入力/IR → lowering → emitters → validation/orchestrationとする。FormalIR、TLA、Leanは`swift-skeleton`へ直接依存させない。

初期版でMCPやdaemonを必須にしない。まずライブラリAPIとCLIを完成させる。必要になれば既存の公開APIを呼ぶ薄いアダプタを追加する。

## 17. 受け入れテスト

以下は将来実装時の必須テストであり、本仕様作成時点で実行済みという意味ではない。

| ID | 対象 | 合格条件 |
|---|---|---|
| A01 | 固定幅整数の減算 | TLA / LeanがSILの結果と一致。手修正不要 |
| A02 | 通常overflowとwrapping | trap / wrap / overflow flagを区別 |
| A03 | if / switch / Optional | 条件・payload・失敗分岐を保持 |
| A04 | block arguments | branch先へのSSA引数束縛が一致 |
| A05 | ループ・再帰 | 全経路を保持。fuel切れを成功にしない |
| A06 | 非停止プログラム | 両形式へ生成可能。停止済みと表示しない |
| A07 | load/store・inout | aliasと書き込みが保存される |
| A08 | 直接呼び出し | calleeも含め結果が一致 |
| A09 | throw/catch | 正常・throw・catch後の経路が一致 |
| A10 | 未解決の外部関数 | 黙ってmodel化せず失敗 |
| A11 | 未対応opcode/attribute | source位置と理由を付けて失敗 |
| A12 | 不具合Actor | 確認→中断→更新の競合を生成モデルが保持 |
| A13 | 修正Actor | 中断のない確認更新へ同一actorの別taskが割り込まない |
| A14 | async apply | 命令名だけでなくcallee型を利用して非同期意味を保持 |
| A15 | executor一致/不一致 | hopの2ケースを区別 |
| A16 | terminal / deadlock | 正常終了を誤検出せず、本物の待ち状態を隠さない |
| A17 | 人工上限 | 境界に到達したらUNKNOWN / BOUND_EXCEEDED |
| A18 | 複数module | private calleeを含む依存閉包を落とさない |
| A19 | debug位置なしSIL | 変換できる。位置不明を明示する |
| A20 | sourceが索引されない | 索引欠落だけで意味を捨てない |
| A21 | 変換証跡の改ざん | validatorが拒否する |
| A22 | 出力式の改ざん | TLA / Leanの更新式変更を検出する |
| A23 | sorry / custom axiom | 推移的依存も含め拒否する |
| A24 | 再生成 | 同一入力・lock・設定でbyte-identical |
| A25 | toolchain差異 | profile不一致を検出し、推測で続行しない |
| A26 | timeout / interrupted check | MODEL_CHECKED / PROVEDにならない |
| A27 | 制御フローの削除 | 分岐片側や異常終了を消すmutationを拒否する |
| A28 | 共有IRの誤変換 | 両backendが同じ誤りでも入力SILとの検査が拒否する |
| A29 | 空の初期状態・矛盾した仮定 | INVALID_SCENARIOを返し、vacuousな検証成功にしない |

### 17.1 Actor競合fixture

初期在庫1、同じactorに対する2つの予約を固定シナリオとする。

不具合版:

```text
在庫確認 → 中断可能な処理 → 在庫減算 → 成功
```

修正版:

```text
同一actorの中断しない隔離区間で、在庫確認 → 在庫減算 → 成功
```

TLA+は、明示したシナリオで不具合版の反例を発見し、修正版では状態探索完了まで同じ性質への反例がないことを確認する。

Leanは、同じ不具合版の反例traceが`Step`関係に従い、指定性質に違反することを検査できなければならない。修正版については、同シナリオの有限証明または一般化された不変条件の証明を行い、どちらかを明記する。

TLAモデルから反例が出ただけで実装のバグと断定せず、SIL参照意味上で再生できることを確認する。

### 17.2 差分・変異テスト

入力SIL／生成IR／両バックエンドを、小さな入力領域と指定スケジュールで比較する。native Swift実行との比較も回帰テストとして行う。

比較テストは有用だが、意味保存の一般的な証明の代替ではない。条件反転、演算変更、型幅変更、suspend削除、状態更新削除、例外経路削除等のmutationが検査で拒否されることを必須にする。

## 18. 実装順序と成果物

### P0 — 意味・入出力契約の固定

- toolchain profile、input bundle、FormalIR schema、diagnosticsを定義。
- 参照semanticsとTCBを文書化。
- 独立validatorの入力境界と、証跡の意味を定義。
- swift-skeletonを公開APIで接続。

### P1 — 最小の両バックエンド縦断

- 固定幅算術、条件分岐、直接呼び出しをSILから変換。
- 同じ入力からTLA+とLeanを自動生成。
- 構文／型／変換対応の検査を通す。
- A01〜A04、A08、A21〜A25の関連テストを通す。

片方だけを実装して、本体の要件を満たしたと報告しない。

### P2 — 逐次実行の拡張

- memory、inout、loop、recursion、enum、throw、trap。
- 非停止の表現とfuelの扱い。
- dependency closureとruntime model registry。

### P3 — Actor / asyncの両形式出力

- executor、task、suspend/resume、runtimeモデル。
- 不具合Actorと修正Actorを同じfixture群で検証。
- 両形式で対応範囲を一致させる。

### P4 — 製品としての完了条件

- strict generation / validate / check / replay。
- support matrix、source mapping、assumptions、provenance、CI policy。
- 全受け入れテストとmutation test。
- TRUST.mdに未検証部分と保証対象を記載。

工程を分割してよいが、完成条件から意味保存検査を後回しにして削除しない。

## 19. Definition of Done

この仕様のv1完成は、次をすべて満たした場合とする。

- 対応プロファイルのSILからTLA+とLeanの両方が、手修正なしに生成される。
- 実行時にAIや自然言語推論を使用しない。
- 対象範囲の命令、型、属性、runtime依存のsemantic coverageが100%である。
- 未対応入力は診断付きで拒否される。
- 小さな算術例だけでなく、Actor再入のfixtureが両形式で動作する。
- 生成物の構文・型と、入力SILとの変換対応が自動検査される。
- 性質の自動証明が未完了の場合、それを生成成功と区別して報告する。
- TLCの有限検査を一般的な証明と表示しない。
- input・output・toolchain・semantics・assumptionsが追跡可能である。
- 生成器／validator／出力のmutation testが通る。
- 同一入力で再現可能な出力になる。
- swift-skeleton本体の改修・forkを必要としない。

## 20. 実装担当への注意

最も避けるべき実装は「SILの一部を読み、もっともらしいTLA+とLeanを書く」ことである。

実装するのは、**SILの実行意味を保持した、検査可能な変換器**である。

読みやすい生成コードより、意味の完全性・追跡性・失敗の明確さを優先する。最適化や人間向けの表示は、正本の意味表現と対応が検査できる範囲で追加する。

## 参考資料・確認対象

以下は本仕様の技術的な背景。機能要件・CLI名・構成・プロファイルは本仕様で定めた新規設計であり、資料に存在する完成済み機能ではない。

- [R1] swift-skeleton README（参照コミット固定）: https://github.com/1amageek/swift-skeleton/blob/fb10ef666a30e892b9f3a4ca0740702c6c621d80/README.md
- [R2] swift-skeleton Package.swift: https://github.com/1amageek/swift-skeleton/blob/fb10ef666a30e892b9f3a4ca0740702c6c621d80/Package.swift
- [R3] Swift Compiler: https://www.swift.org/documentation/swift-compiler/
- [R4] Swift SIL overview: https://github.com/swiftlang/swift/blob/main/docs/SIL/SIL.md
- [R5] Swift SIL Types（Async Functions）: https://github.com/swiftlang/swift/blob/main/docs/SIL/Types.md
- [R6] Swift SIL Instructions: https://github.com/swiftlang/swift/blob/main/docs/SIL/Instructions.md
- [R7] Lean Recursive Definitions: https://lean-lang.org/doc/reference/latest/Definitions/Recursive-Definitions/
- [R8] Validating a Lean Proof: https://lean-lang.org/doc/reference/latest/ValidatingProofs/
- [R9] TLC Configuration: https://learning.tlapl.us/intro/tlc-config/

Swift / Leanのmain・latest資料は開発開始時の参照である。実装では選定したリリース／コミットへ固定し、適用した意味規則との対応を保存する。
