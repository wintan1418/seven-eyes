// Parallel Scripture — artboards (Ancient Epistle aesthetic)
// Each artboard is a self-contained snapshot of one app state.

/* =========================================================
   Shared chrome bits
   ========================================================= */

function TopBar({ studyName = "Untitled Study", panes = 4, sync = false, saved = true }) {
  return (
    <div className="ps-topbar">
      <div className="ps-brand">
        <span className="cross">☩</span>
        <span>PARALLEL · SCRIPTURE</span>
      </div>
      <div className="ps-study-name">
        <span className="orn">❦</span>
        <span>{studyName}</span>
        <span className="pencil">✎</span>
      </div>
      <div className="ps-topbar-actions">
        <div className="ps-pane-picker" title="Pane count">
          {[1, 2, 3, 4].map((n) => (
            <button key={n} className={panes === n ? "is-on" : ""}>{n}</button>
          ))}
        </div>
        <button className={"ps-tb-btn " + (sync ? "is-active" : "")}>
          <span className="dot" />
          Sync Scroll
        </button>
        <button className="ps-tb-btn">⌖ X-Refs</button>
        <button className="ps-tb-btn">{saved ? "✓ Saved" : "Save"}</button>
      </div>
    </div>
  );
}

function Sidebar({ active = null, withWelcome = false }) {
  const recents = [
    { id: "just", name: "Justification — Sept 14 sermon", meta: "4 panes · yesterday" },
    { id: "ima", name: "Imago Dei across the Pentateuch", meta: "3 panes · 4 days ago" },
    { id: "sab", name: "Sabbath rest — Hebrews 4 study", meta: "2 panes · 1 week ago" },
    { id: "psa", name: "Psalm 23 · translation atlas", meta: "4 panes · 2 weeks ago" },
    { id: "rev", name: "Seven letters of Revelation", meta: "1 pane · 3 weeks ago" },
  ];
  const pinned = [
    { id: "ser", name: "Sermon notebook · Romans cycle", meta: "Pinned" },
  ];
  return (
    <aside className="ps-sidebar">
      <div className="ps-sidebar-head">
        <div className="ps-sidebar-title">The Scriptorium</div>
        <button className="ps-new-study">
          <span className="plus">✚</span>
          <span>New Study</span>
        </button>
      </div>
      <div className="ps-sidebar-section">Pinned</div>
      <div className="ps-study-list" style={{ paddingBottom: 0 }}>
        {pinned.map((s) => (
          <div key={s.id} className={"ps-study-item " + (active === s.id ? "is-active" : "")}>
            <div className="nm">{s.name}</div>
            <div className="meta">{s.meta}</div>
          </div>
        ))}
      </div>
      <div className="ps-sidebar-section">Recent</div>
      <div className="ps-study-list">
        {recents.map((s) => (
          <div key={s.id} className={"ps-study-item " + (active === s.id ? "is-active" : "")}>
            <div className="nm">{s.name}</div>
            <div className="meta">{s.meta}</div>
          </div>
        ))}
      </div>
    </aside>
  );
}

const ROMAN = ["I", "II", "III", "IV"];

function PaneHead({ index, reference, translation = "KJV", placeholder = "Type a reference…", focused = false }) {
  return (
    <div className="ps-pane-head">
      <div className="ps-pane-index">{ROMAN[index]}</div>
      <div className={"ps-search" + (focused ? " is-focused" : "") + (!reference ? " empty" : "")} style={{display:'flex',alignItems:'center'}}>
        {reference || placeholder}
      </div>
      <div className="ps-trans">
        <span>{translation}</span>
        <span className="caret">▾</span>
      </div>
      <button className="ps-pane-tool" title="Cross references">⌖</button>
      <button className="ps-pane-tool" title="More">⋯</button>
    </div>
  );
}

function VerseBody({ children, refTitle, translationName, dropCap = false }) {
  return (
    <div className="ps-verses">
      <div className="ref-title">
        <span>{refTitle}</span>
        {translationName && <span className="tag">· {translationName}</span>}
      </div>
      <div className="rule" />
      <div className={dropCap ? "ps-verse-body with-dropcap" : "ps-verse-body"}>
        {children}
      </div>
    </div>
  );
}

function Verse({ n, children, selected = false }) {
  return (
    <span className={"ps-verse" + (selected ? " is-selected" : "")}>
      <span className="ps-vnum">{n}</span>{children}{" "}
    </span>
  );
}

function NotesBlock({ children, lastSaved = "Saved a moment ago" }) {
  return (
    <div className="ps-notes">
      <div className="ps-notes-head">
        Notes <span className="saving">— {lastSaved}</span>
      </div>
      <div className={"ps-notes-body" + (!children ? " empty" : "")}>
        {children || "Write a thought, an outline, a cross-reference you want to remember…"}
      </div>
    </div>
  );
}

function EmptyPane({ index }) {
  return (
    <div className="ps-pane-empty">
      <div className="orn">❦</div>
      <div className="lead">Pane {ROMAN[index]} stands ready</div>
      <div className="hint">Type a reference — <em>Jn 3:16, Rom 5, 1 Cor 13:1‑13</em> — to summon the text.</div>
      <div style={{display:'flex',gap:6,marginTop:6}}>
        <span className="kbd">⌘ K</span>
        <span className="kbd">{index + 1}</span>
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 1 · The Scriptorium (welcome / studies index)
   ========================================================= */

function S1_Scriptorium() {
  return (
    <div className="ps-root">
      <TopBar studyName="The Scriptorium" panes={4} sync={false} saved={true} />
      <div className="ps-shell">
        <Sidebar active="just" />
        <main className="ps-workspace" style={{ gridTemplateColumns: "1fr", gridTemplateRows: "1fr" }}>
          <div className="ps-welcome">
            <div className="eyebrow">☩ &nbsp; A Quiet Desk For The Word &nbsp; ☩</div>
            <h1>Welcome back, Pastor.</h1>
            <div className="rule-orn">
              <span className="line" />
              <span>❦</span>
              <span className="line" />
            </div>
            <div className="verse-of-day">
              “Open thou mine eyes, that I may behold wondrous things out of thy law.”
              <span className="ref">Psalm CXIX · 18 · KJV</span>
            </div>
            <div className="cta-row">
              <button className="cta">✚ &nbsp; Begin a New Study</button>
              <button className="cta secondary">↻ &nbsp; Resume Justification — Sept 14</button>
            </div>
            <div style={{marginTop:38,fontFamily:'"Cinzel",serif',fontSize:10,letterSpacing:'0.22em',color:'var(--sepia-mute)',textTransform:'uppercase'}}>
              <span>kjv · asv · bsb · web · darby · ylt</span>
              <span style={{margin:'0 10px',color:'var(--gold)'}}>·</span>
              <span>tsk cross-references · seeded locally</span>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 2 · A New Codex (4 empty panes, modal naming open)
   ========================================================= */

function S2_NewCodex() {
  return (
    <div className="ps-root">
      <TopBar studyName="Untitled Study" panes={4} sync={false} saved={false} />
      <div className="ps-shell">
        <Sidebar />
        <main className="ps-workspace cols-4">
          {[0, 1, 2, 3].map((i) => (
            <section className="ps-pane" key={i}>
              <PaneHead index={i} reference={null} translation={["KJV","KJV","KJV","KJV"][i]} />
              <EmptyPane index={i} />
            </section>
          ))}
        </main>
      </div>

      {/* Modal: name your study */}
      <div className="ps-modal-shroud">
        <div className="ps-modal">
          <span className="corner tl">❦</span>
          <span className="corner tr">❦</span>
          <span className="corner bl">❦</span>
          <span className="corner br">❦</span>
          <h2>· The Naming of a Study ·</h2>
          <div className="title">What shall we call this work?</div>
          <div className="field-label">Title</div>
          <input
            className="field"
            defaultValue="Justification — Sept 14 sermon"
          />
          <div className="field-label">Pane arrangement</div>
          <div className="seg">
            <button>I · Single</button>
            <button>II · Pair</button>
            <button>III · Triptych</button>
            <button className="is-on">IV · Codex</button>
          </div>
          <div className="actions">
            <button className="btn secondary">Cancel</button>
            <button className="btn primary">Open Study</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 3 · Romans 5:1 across four translations
   ========================================================= */

function S3_FourTranslations() {
  return (
    <div className="ps-root">
      <TopBar studyName="Romans 5 · Translation Atlas" panes={4} sync={true} saved={true} />
      <div className="ps-shell">
        <Sidebar active="psa" />
        <main className="ps-workspace cols-4">
          {/* I — KJV */}
          <section className="ps-pane">
            <PaneHead index={0} reference="Romans 5:1–5" translation="KJV" />
            <VerseBody refTitle="Romans V" translationName="King James Version">
              <span className="ps-dropcap">T</span>
              <Verse n="1">herefore being justified by faith, we have peace with God through our Lord Jesus Christ:</Verse>
              <Verse n="2">By whom also we have access by faith into this grace wherein we stand, and rejoice in hope of the glory of God.</Verse>
              <Verse n="3">And not only so, but we glory in tribulations also: knowing that tribulation worketh patience;</Verse>
              <Verse n="4">And patience, experience; and experience, hope:</Verse>
              <Verse n="5">And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the Holy Ghost which is given unto us.</Verse>
            </VerseBody>
            <NotesBlock lastSaved="Saved 2m ago">
              Note the <em>therefore</em>—Paul builds upon Abraham's reckoning in ch. 4. The peace is positional, not emotional.
            </NotesBlock>
          </section>

          {/* II — ASV */}
          <section className="ps-pane">
            <PaneHead index={1} reference="Romans 5:1–5" translation="ASV" />
            <VerseBody refTitle="Romans V" translationName="American Standard Version">
              <Verse n="1">Being therefore justified by faith, we have peace with God through our Lord Jesus Christ;</Verse>
              <Verse n="2">through whom also we have had our access by faith into this grace wherein we stand; and we rejoice in hope of the glory of God.</Verse>
              <Verse n="3">And not only so, but we also rejoice in our tribulations: knowing that tribulation worketh stedfastness;</Verse>
              <Verse n="4">and stedfastness, approvedness; and approvedness, hope:</Verse>
              <Verse n="5">and hope putteth not to shame; because the love of God hath been shed abroad in our hearts through the Holy Spirit which was given unto us.</Verse>
            </VerseBody>
            <NotesBlock lastSaved="">
              {null}
            </NotesBlock>
          </section>

          {/* III — BSB */}
          <section className="ps-pane">
            <PaneHead index={2} reference="Romans 5:1–5" translation="BSB" />
            <VerseBody refTitle="Romans V" translationName="Berean Standard Bible">
              <Verse n="1">Therefore, since we have been justified through faith, we have peace with God through our Lord Jesus Christ,</Verse>
              <Verse n="2">through whom we have gained access by faith into this grace in which we now stand. And we rejoice in the hope of the glory of God.</Verse>
              <Verse n="3">Not only that, but we also rejoice in our sufferings, because we know that suffering produces perseverance;</Verse>
              <Verse n="4">perseverance, character; and character, hope.</Verse>
              <Verse n="5">And hope does not disappoint us, because God's love has been poured out into our hearts through the Holy Spirit, who has been given to us.</Verse>
            </VerseBody>
            <NotesBlock lastSaved="">
              {null}
            </NotesBlock>
          </section>

          {/* IV — Greek interlinear */}
          <section className="ps-pane">
            <PaneHead index={3} reference="Romans 5:1" translation="GRK" />
            <VerseBody refTitle="Πρὸς Ῥωμαίους Ε" translationName="SBL Greek New Testament">
              <Verse n="1">
                Δικαιωθέντες οὖν ἐκ πίστεως εἰρήνην ἔχομεν πρὸς τὸν θεὸν διὰ τοῦ κυρίου ἡμῶν Ἰησοῦ Χριστοῦ,
                <span className="ps-greek">justified · therefore · by faith · peace · we have · toward · God · through · the Lord · of us · Jesus · Christ</span>
              </Verse>
              <div style={{
                marginTop: 18,
                padding: '12px 14px',
                background: 'rgba(138, 36, 24, 0.06)',
                border: '1px solid rgba(138, 36, 24, 0.25)',
                borderRadius: 2,
              }}>
                <div style={{fontFamily:'"Cinzel",serif',fontWeight:600,fontSize:10,letterSpacing:'0.22em',color:'var(--rubric)',textTransform:'uppercase',marginBottom:6}}>
                  Δικαιωθέντες · G1344
                </div>
                <div style={{fontSize:14,lineHeight:1.55,color:'var(--ink-soft)'}}>
                  <em>dikaiōthentes</em> — aorist passive participle of <em>dikaioō</em>:
                  to declare, pronounce, or treat as righteous. Aorist tense — a completed act.
                </div>
                <div style={{marginTop:8,fontSize:12,color:'var(--sepia-mute)',fontStyle:'italic'}}>
                  occurs 39× across Paul · 21× in Romans
                </div>
              </div>
            </VerseBody>
            <NotesBlock lastSaved="Saved just now">
              The passive voice matters: <em>we are declared righteous</em>—it is done unto us, not by us.
            </NotesBlock>
          </section>
        </main>
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 4 · Cross-Reference Drawer Open
   ========================================================= */

function S4_CrossRefs() {
  return (
    <div className="ps-root">
      <TopBar studyName="John 3 · Born of the Spirit" panes={2} sync={false} saved={true} />
      <div className="ps-shell">
        <Sidebar />
        <main className="ps-workspace cols-2">
          {/* I — John 3:16 KJV */}
          <section className="ps-pane">
            <PaneHead index={0} reference="John 3:14–17" translation="KJV" />
            <VerseBody refTitle="John III" translationName="King James Version">
              <Verse n="14">And as Moses lifted up the serpent in the wilderness, even so must the Son of man be lifted up:</Verse>
              <Verse n="15">That whosoever believeth in him should not perish, but have eternal life.</Verse>
              <Verse n="16" selected>
                For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.
              </Verse>
              <Verse n="17">For God sent not his Son into the world to condemn the world; but that the world through him might be saved.</Verse>
              {/* highlight popover floating over verse 16 */}
              <div className="ps-hl-popover" style={{ left: 24, top: 218 }}>
                <span className="ps-hl-swatch ochre" />
                <span className="ps-hl-swatch sage" />
                <span className="ps-hl-swatch cobalt" />
                <span className="ps-hl-swatch rose" />
                <span className="divider" />
                <span className="x-ref">⌖ X-Refs</span>
                <span className="x-ref">✎ Note</span>
              </div>
            </VerseBody>
            <NotesBlock lastSaved="Saved 12s ago">
              Cross-reference sweep ↗ in pane II. <span className="hl-ochre">"only begotten"</span> — note Greek <em>monogenēs</em>, unique-of-its-kind.
            </NotesBlock>
          </section>

          {/* II — BSB */}
          <section className="ps-pane">
            <PaneHead index={1} reference="John 3:14–17" translation="BSB" />
            <VerseBody refTitle="John III" translationName="Berean Standard Bible">
              <Verse n="14">Just as Moses lifted up the snake in the wilderness, so the Son of Man must be lifted up,</Verse>
              <Verse n="15">that everyone who believes in Him may have eternal life.</Verse>
              <Verse n="16">For God so loved the world that He gave His one and only Son, that everyone who believes in Him shall not perish but have eternal life.</Verse>
              <Verse n="17">For God did not send His Son into the world to condemn the world, but to save the world through Him.</Verse>
            </VerseBody>
            <NotesBlock lastSaved="">{null}</NotesBlock>
          </section>
        </main>

        {/* drawer */}
        <aside className="ps-drawer">
          <div className="ps-drawer-head">
            <div className="ps-drawer-eyebrow">
              <span>⌖ &nbsp; Cross References</span>
              <button className="close">✕</button>
            </div>
            <div className="ps-drawer-title">John 3 · 16</div>
            <div className="ps-drawer-sub">Treasury of Scripture Knowledge · 42 references</div>
          </div>
          <div className="ps-drawer-list">
            {[
              { ref: "Romans 5:8", votes: 84, text: "But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us." },
              { ref: "1 John 4:9", votes: 76, text: "In this was manifested the love of God toward us, because that God sent his only begotten Son into the world…" },
              { ref: "Romans 8:32", votes: 71, text: "He that spared not his own Son, but delivered him up for us all, how shall he not with him also freely give us all things?" },
              { ref: "1 John 4:10", votes: 63, text: "Herein is love, not that we loved God, but that he loved us, and sent his Son to be the propitiation for our sins." },
              { ref: "Galatians 2:20", votes: 58, text: "I am crucified with Christ… who loved me, and gave himself for me." },
              { ref: "John 3:36", votes: 52, text: "He that believeth on the Son hath everlasting life…" },
            ].map((r, i) => (
              <div className="ps-xref" key={r.ref}>
                <div className="ps-xref-head">
                  <div className="ps-xref-ref">{r.ref}</div>
                  <div className="ps-xref-votes">
                    {"●".repeat(Math.min(5, Math.round(r.votes / 18)))}
                    <span style={{ marginLeft: 4 }}>· {r.votes}</span>
                  </div>
                </div>
                <div className="ps-xref-text">{r.text}</div>
                <div className="ps-xref-actions">
                  <button className="ps-xref-load">▸ Pane I</button>
                  <button className="ps-xref-load">▸ Pane II</button>
                </div>
              </div>
            ))}
          </div>
        </aside>
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 5 · Justification florilegium (the pastor's actual study)
   ========================================================= */

function S5_Justification() {
  return (
    <div className="ps-root">
      <TopBar studyName="Justification — Sept 14 sermon" panes={4} sync={false} saved={true} />
      <div className="ps-shell">
        <Sidebar active="just" />
        <main className="ps-workspace cols-4">
          {/* I — Romans 5:1 ESV-substitute (BSB) */}
          <section className="ps-pane">
            <PaneHead index={0} reference="Romans 5:1" translation="BSB" />
            <VerseBody refTitle="Romans V · 1" translationName="Berean Standard Bible">
              <span className="ps-dropcap">T</span>
              <Verse n="1">herefore, since we have been{" "}
                <span className="hl-ochre">justified through faith</span>,
                we have <span className="hl-sage">peace with God</span>{" "}
                through our Lord Jesus Christ,
              </Verse>
              <div style={{
                marginTop: 18, padding: '10px 12px', background: 'rgba(108, 132, 78, 0.12)',
                borderLeft: '2px solid var(--sepia-mute)', fontStyle: 'italic',
                fontFamily: '"EB Garamond",serif', fontSize: 14, lineHeight: 1.55, color: 'var(--ink-soft)'
              }}>
                The <em>therefore</em> reaches back to Abraham (ch. 4)—a Gentile
                righteousness reckoned before Sinai. <strong>Peace</strong> = positional,
                not affective.
              </div>
            </VerseBody>
            <NotesBlock lastSaved="Saved 4s ago">
              <strong>Open with this verse.</strong><br/>
              Hammer the perfect tense — <em>have been justified</em>. Settled. Not a verdict still being weighed.
            </NotesBlock>
          </section>

          {/* II — Galatians 2:16 KJV */}
          <section className="ps-pane">
            <PaneHead index={1} reference="Galatians 2:16" translation="KJV" />
            <VerseBody refTitle="Galatians II · 16" translationName="King James Version">
              <Verse n="16">
                Knowing that a man is{" "}
                <span className="hl-rose">not justified by the works of the law</span>,
                but by the <span className="hl-ochre">faith of Jesus Christ</span>,
                even we have believed in Jesus Christ, that we might be
                <span className="hl-ochre"> justified by the faith of Christ</span>,
                and not by the works of the law:{" "}
                <span className="hl-rose">for by the works of the law shall no flesh be justified</span>.
              </Verse>
              <div style={{
                marginTop:14,fontFamily:'"Cinzel",serif',fontSize:9.5,letterSpacing:'0.22em',
                color:'var(--rubric)',textTransform:'uppercase'
              }}>
                Three uses of <em>justify</em> · One verse
              </div>
            </VerseBody>
            <NotesBlock lastSaved="Saved 1m ago">
              Paul to <em>Peter</em>, in front of the church. The doctrine is born of confrontation, not abstraction.
            </NotesBlock>
          </section>

          {/* III — Ephesians 2:8-9 KJV */}
          <section className="ps-pane">
            <PaneHead index={2} reference="Ephesians 2:8–9" translation="KJV" />
            <VerseBody refTitle="Ephesians II · 8–9" translationName="King James Version">
              <Verse n="8">For <span className="hl-cobalt">by grace are ye saved through faith</span>; and that not of yourselves: it is the <span className="hl-ochre">gift of God</span>:</Verse>
              <Verse n="9">Not of works, lest any man should boast.</Verse>
              <div style={{
                marginTop: 16, padding: '10px 12px', background: 'rgba(72, 96, 128, 0.10)',
                borderLeft: '2px solid var(--sepia-mute)', fontFamily: '"EB Garamond",serif',
                fontSize: 14, lineHeight: 1.55, color: 'var(--ink-soft)', fontStyle: 'italic'
              }}>
                The neuter pronoun <em>τοῦτο</em> ("that") most naturally refers to
                the whole salvation — grace, faith, all of it — as the gift.
              </div>
            </VerseBody>
            <NotesBlock lastSaved="Saved 3m ago">
              Close the sermon here. <em>Lest any man should boast</em> — the
              pastoral application: humility is not added to grace, it is grace's effect.
            </NotesBlock>
          </section>

          {/* IV — Habakkuk 2:4 (the quotation root) */}
          <section className="ps-pane">
            <PaneHead index={3} reference="Habakkuk 2:4" translation="KJV" />
            <VerseBody refTitle="Habakkuk II · 4" translationName="King James Version">
              <Verse n="4">Behold, his soul which is lifted up is not upright in him: but{" "}
                <span className="hl-ochre">the just shall live by his faith</span>.
              </Verse>
              <div style={{
                marginTop: 22,
                fontFamily: '"Cinzel",serif', fontSize: 10, letterSpacing: '0.22em',
                color: 'var(--sepia)', textTransform: 'uppercase', marginBottom: 8
              }}>
                ⌖ Echoed in
              </div>
              {[
                { ref: "Rom 1:17", text: "The just shall live by faith." },
                { ref: "Gal 3:11", text: "The just shall live by faith." },
                { ref: "Heb 10:38", text: "Now the just shall live by faith…" },
              ].map((e) => (
                <div key={e.ref} style={{
                  padding: '8px 0', borderTop: '1px dashed rgba(138, 116, 68, 0.35)',
                  display: 'flex', gap: 12, alignItems: 'baseline'
                }}>
                  <span style={{
                    fontFamily: '"Cinzel",serif', fontWeight: 600, fontSize: 10,
                    letterSpacing: '0.18em', color: 'var(--rubric)', minWidth: 70
                  }}>{e.ref}</span>
                  <span style={{ fontSize: 14, color: 'var(--ink-soft)', fontStyle: 'italic' }}>{e.text}</span>
                </div>
              ))}
            </VerseBody>
            <NotesBlock lastSaved="Saved 8m ago">
              The thread runs from <em>Habakkuk</em> — written to a despairing prophet — through Paul's two great epistles to Hebrews. <strong>Same five words.</strong>
            </NotesBlock>
          </section>
        </main>
      </div>
      <div className="ps-toast">
        <span className="check">✓</span> Highlight saved · Galatians 2:16 · Ochre
      </div>
    </div>
  );
}

/* =========================================================
   Scenario 6 · Synchronized Scroll, full chapter (Psalm 23)
   ========================================================= */

function S6_SyncScroll() {
  // The shared chapter content — appears across all four panes
  const psalm23 = [
    {
      n: 1,
      KJV: "The Lord is my shepherd; I shall not want.",
      ASV: "Jehovah is my shepherd; I shall not want.",
      BSB: "The LORD is my shepherd; I shall not want.",
      DBY: "Jehovah is my shepherd; I shall not want.",
    },
    {
      n: 2,
      KJV: "He maketh me to lie down in green pastures: he leadeth me beside the still waters.",
      ASV: "He maketh me to lie down in green pastures; He leadeth me beside still waters.",
      BSB: "He makes me lie down in green pastures; He leads me beside quiet waters.",
      DBY: "He maketh me to lie down in green pastures; he leadeth me beside still waters.",
    },
    {
      n: 3,
      KJV: "He restoreth my soul: he leadeth me in the paths of righteousness for his name's sake.",
      ASV: "He restoreth my soul: He guideth me in the paths of righteousness for his name's sake.",
      BSB: "He restores my soul; He guides me in paths of righteousness for the sake of His name.",
      DBY: "He restoreth my soul; he leadeth me in paths of righteousness for his name's sake.",
    },
    {
      n: 4,
      KJV: "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me.",
      ASV: "Yea, though I walk through the valley of the shadow of death, I will fear no evil; for thou art with me; Thy rod and thy staff, they comfort me.",
      BSB: "Even though I walk through the valley of the shadow of death, I will fear no evil, for You are with me; Your rod and Your staff, they comfort me.",
      DBY: "Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff, they comfort me.",
    },
    {
      n: 5,
      KJV: "Thou preparest a table before me in the presence of mine enemies: thou anointest my head with oil; my cup runneth over.",
      ASV: "Thou preparest a table before me in the presence of mine enemies: Thou hast anointed my head with oil; my cup runneth over.",
      BSB: "You prepare a table before me in the presence of my enemies. You anoint my head with oil; my cup overflows.",
      DBY: "Thou preparest a table before me in the presence of mine enemies; thou hast anointed my head with oil; my cup runneth over.",
    },
  ];

  const Pane = ({ idx, code, name }) => (
    <section className="ps-pane">
      <PaneHead index={idx} reference="Psalm 23" translation={code} />
      <VerseBody refTitle="Psalm XXIII" translationName={name}>
        {idx === 0 && <span className="ps-dropcap">A</span>}
        {idx === 0 && <span style={{
          fontFamily: '"EB Garamond",serif', fontSize: 13, color: 'var(--sepia)',
          fontStyle: 'italic', display: 'block', marginBottom: 8
        }}>A Psalm of David.</span>}
        {psalm23.map((v) => (
          <Verse n={v.n} key={v.n}>{v[code === "DBY" ? "DBY" : code]}</Verse>
        ))}
      </VerseBody>
      <NotesBlock lastSaved={idx === 0 ? "Saved 30s ago" : ""}>
        {idx === 0 ? "Compare v.2 — KJV's 'still waters' vs BSB's 'quiet waters' — both for menuchot, waters of rest." : null}
      </NotesBlock>
    </section>
  );

  return (
    <div className="ps-root">
      <TopBar studyName="Psalm 23 · Translation Atlas" panes={4} sync={true} saved={true} />
      <div className="ps-shell">
        <Sidebar active="psa" />
        <main className="ps-workspace cols-4">
          <Pane idx={0} code="KJV" name="King James Version" />
          <Pane idx={1} code="ASV" name="American Standard Version" />
          <Pane idx={2} code="BSB" name="Berean Standard Bible" />
          <Pane idx={3} code="DBY" name="Darby Translation" />
        </main>
      </div>

      <div className="ps-shortcut-hint">
        <span className="k">⌘ K</span><span>Focus reference</span>
        <span className="k">1–4</span><span>Switch pane</span>
        <span className="k">⌘ S</span><span>Save study</span>
        <span className="k">⌘ D</span><span>Duplicate to next pane</span>
        <span className="k">X</span><span>Cross-references</span>
        <span className="k">Esc</span><span>Close drawer</span>
      </div>
    </div>
  );
}

/* =========================================================
   Canvas root
   ========================================================= */

function App() {
  return (
    <DesignCanvas>
      <DCSection id="overview" title="Parallel Scripture" subtitle="A multi-pane Bible study workspace · Hotwire + Rails 8 · drawn in the manner of an ancient epistle">
        <DCArtboard id="s1" label="I · The Scriptorium" width={1440} height={900}>
          <S1_Scriptorium />
        </DCArtboard>
        <DCArtboard id="s2" label="II · A New Codex" width={1440} height={900}>
          <S2_NewCodex />
        </DCArtboard>
      </DCSection>

      <DCSection id="comparison" title="Comparison Modes" subtitle="Same verse, different translations · and different verses, mixed">
        <DCArtboard id="s3" label="III · Romans V · Four Translations" width={1440} height={900}>
          <S3_FourTranslations />
        </DCArtboard>
        <DCArtboard id="s5" label="V · Justification — the pastor's florilegium" width={1440} height={900}>
          <S5_Justification />
        </DCArtboard>
      </DCSection>

      <DCSection id="depth" title="Going Deeper" subtitle="Cross-references, highlights, synchronized reading">
        <DCArtboard id="s4" label="IV · Cross-Reference Drawer" width={1440} height={900}>
          <S4_CrossRefs />
        </DCArtboard>
        <DCArtboard id="s6" label="VI · Synchronia · Sync Scroll + Shortcuts" width={1440} height={900}>
          <S6_SyncScroll />
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
