(function () {

  function sec(t) { return '<div class="form-section">' + esc(t) + '</div>'; }
  function empty() { return '<div class="form-field"></div>'; }
  function tagOf(text, color) {
    return '<span class="tag ' + esc(color || '') + '">' + esc(text) + '</span>';
  }
  function yearText(v) { return v ? yearLabel(v) : '-'; }

  var id = new URLSearchParams(location.search).get('id');
  var list = ClassStore.load();
  var src = list.filter(function (r) { return r.id === id; })[0];
  if (!src) {
    MessageDialog.show('対象のクラスが見つかりません', function () { location.href = 'class_list.html'; });
    return;
  }

  var c = ClassStore.COURSES[src.courseCode] || {};
  var p = ClassStore.PROJECTS[src.projectCode] || {};
  $('subLine').textContent = (c.name || src.courseCode || '') + '　' + src.lessonNo + '　' + src.start + '〜' + src.end;
  $('cancelLink').href = 'class_modify.html?id=' + encodeURIComponent(src.id);
  (function () {
    var off = src.status === OperatingStatusStore.nameOf('STOPPED');
    var t = $('statusAllToggle');
    t.classList.toggle('off', off);
    var label = t.parentNode.querySelector('span');
    label.textContent = off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    t.addEventListener('click', function () {
      var isOn = !t.classList.contains('off');
      t.classList.toggle('off', isOn);
      label.textContent = isOn ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    });
  })();


  function sourceHtml() {
    var projectPart = [
      sec('案件'),
      '<div class="form-field full"><div class="form-value">' + [
        '<span>' + esc(yearText(src.year)) + '</span>',
        '<span>' + esc(src.projectCode || '') + '</span>',
        p.name ? '<span>' + esc(p.name) + '</span>' : '',
        p.sales ? tagOf(SalesTypeStore.nameOf(p.sales), SalesTypeStore.colorOf(p.sales)) : '',
        p.part ? tagOf(ParticipationTypeStore.nameOf(p.part), ParticipationTypeStore.colorOf(p.part)) : ''
      ].filter(Boolean).join('') + '</div></div>',
    ].join('');
    var coursePart = [
      sec('コース'),
      '<div class="form-field full"><div class="form-value">' + [
        '<span>' + esc(src.courseCode || '') + '</span>',
        '<span>' + esc(c.name || '') + '</span>',
        c.part ? tagOf(ParticipationTypeStore.nameOf(c.part), ParticipationTypeStore.colorOf(c.part)) : '',
        '<span>' + esc('版' + (src.version || '-')) + '</span>',
        c.delivery ? '<span class="form-value-note">推奨：<span class="tag ' + esc(DeliveryTypeStore.colorOf(c.delivery)) + '">' + esc(DeliveryTypeStore.nameOf(c.delivery)) + '</span> ' + esc(c.schedule || '') + ' 講師 メイン' + (c.mainTeachers === undefined ? '-' : c.mainTeachers) + '人・サブ' + (c.subTeachers === undefined ? '-' : c.subTeachers) + '人</span>' : ''
      ].filter(Boolean).join('') + '</div></div>',
    ].join('');
    return '<div id="projectPart" class="contents">' + projectPart + '</div><div id="coursePart" class="contents">' + coursePart + '</div>';
  }
  $('copyItems').innerHTML = sourceHtml();
  $('projectPart').style.display = 'none';



  function bindEndCalc(k) {
    var startEl = document.querySelector('[data-k="' + k + '"][data-f="start"]');
    var endEl = document.querySelector('[data-k="' + k + '"][data-f="end"]');
    if (!startEl || !endEl) return;
    var endTouched = false;
    endEl.addEventListener('click', function () { endTouched = true; }, true);
    function calc() {
      if (endTouched) return;
      var course = CourseStore.load().filter(function (x) { return x.code === src.courseCode; })[0];
      var out = calcEndDate(ownText(startEl), course ? course.days : null);
      if (out) endEl.innerHTML = out + '<span class="caret">▾</span>';
    }
    new MutationObserver(calc).observe(startEl, { childList: true, characterData: true, subtree: true });
  }

  function numberSelect(k, f, options, value, required) {
    return '<div class="form-field"><label>' + esc(f.label) + (required ? '<span class="req">必須</span>' : '') + '</label>' +
      '<div class="form-control number-select" data-k="' + k + '" data-f="' + f.key + '" data-options="' + esc(options) + '">' +
      '<input type="text" inputmode="numeric" value="' + esc(value) + '"><span class="caret">▾</span></div></div>';
  }

  function renderPerCopy() {
    var count = parseInt($('copyCount').value, 10);
    if (!count || count < 1 || count > 10) { $('perCopy').innerHTML = ''; return; }
    var types = LocationTypeStore.load();
    var byType = LocationStore.namesByType();
    var html = '';
    for (var k = 1; k <= count; k++) {
      var typeRadios = types.map(function (t) {
        return '<label class="radio-option"><input type="radio" name="locationType-' + k + '" value="' + esc(t.code) + '"' + (t.code === src.locationType ? ' checked' : '') + '><span class="radio-dot"></span><span class="tag ' + tagClassOf('locationType') + ' ' + esc(t.color) + '">' + esc(t.name) + '</span></label>';
      }).join('');
      var initName = '';
      var initOptions = (byType[src.locationType] || []).join(',');
      html += '<div class="form-section copy-section">複製 ' + k + '</div>' +
        '<div class="form-section">クラス</div>' +
        '<div class="form-field"><label>開始日<span class="req">必須</span></label><div class="form-control js-date" data-k="' + k + '" data-f="start">' + esc(src.start) + '<span class="caret">▾</span></div></div>' +
        '<div class="form-field"><label>終了日<span class="req">必須</span></label><div class="form-control js-date" data-k="' + k + '" data-f="end">' + esc(src.end) + '<span class="caret">▾</span></div></div>' +
        '<div class="form-section">受講生</div>' +
        numberSelect(k, { key: 'people', label: '受講人数' }, '10,15,20,24,30,35,40,50', '', false) + empty() +
        '<div class="form-section">講師</div>' +
        numberSelect(k, { key: 'mainTeachers', label: '予定講師数（メイン）' }, '0,1,2,3,4,5', src.mainTeachers == null ? '' : src.mainTeachers, true) +
        numberSelect(k, { key: 'subTeachers', label: '予定講師数（サブ）' }, '0,1,2,3,4,5', src.subTeachers == null ? '' : src.subTeachers, true) +
        '<div class="form-section">ロケーション</div>' +
        '<div class="form-field full"><label>ロケーション区分<span class="req">必須</span></label><div class="radio-group" data-k="' + k + '">' + typeRadios + '</div></div>' +
        '<div class="form-field"><label>ロケーション名</label><div class="form-control js-select" data-k="' + k + '" data-f="locationName" data-value="' + esc(initName) + '" data-options="' + esc(initOptions) + '">' + esc(initName || '選択してください') + '<span class="caret">▾</span></div></div>' +
        '<div class="form-section">その他</div>' +
        '<div class="form-field full"><label>備考</label><textarea class="form-control textarea auto-grow" data-min="68" data-k="' + k + '" data-f="memo" placeholder="例）欠席者ありのため人数変更の可能性あり"></textarea></div>';
    }
    $('perCopy').innerHTML = html;
    bindFormControls($('perCopy'));
    for (var e = 1; e <= count; e++) bindEndCalc(e);
    for (var j = 1; j <= count; j++) {
      (function (kk) {
        document.querySelectorAll('input[name="locationType-' + kk + '"]').forEach(function (radio) {
          radio.addEventListener('change', function () {
            var target = document.querySelector('[data-k="' + kk + '"][data-f="locationName"]');
            var names = byType[radio.value] || [];
            if (target) window.jsSelectSetOptions(target, names);
          });
        });
      })(j);
    }
  }
  (function () {
    var seg = $('infoSeg');
    var opts = seg.querySelectorAll('.seg-opt');
    Array.prototype.forEach.call(opts, function (btn) {
      btn.addEventListener('click', function () {
        var show = btn.getAttribute('data-v') === 'show';
        Array.prototype.forEach.call(opts, function (b) { b.classList.toggle('is-active', b === btn); });
        $('projectPart').style.display = show ? '' : 'none';
      });
    });
  })();
  (function () {
    var sw = $('relateToSource');
    var label = sw.parentNode.querySelector('span');
    sw.addEventListener('click', function () {
      var off = sw.classList.toggle('off');
      label.textContent = off ? 'なし' : 'あり';
    });
  })();
  $('copyCount').addEventListener('input', renderPerCopy);
  renderPerCopy();

  function fieldEl(k, f) { return document.querySelector('[data-k="' + k + '"][data-f="' + f + '"]'); }
  function memoVal(k) { var el = fieldEl(k, 'memo'); return el ? el.value.trim() : ''; }
  function dateVal(k, f) { var el = fieldEl(k, f); return el ? ownText(el) : ''; }
  function numVal(k, f) { var el = fieldEl(k, f); return el ? el.querySelector('input').value.trim() : ''; }
  function typeCode(k) {
    var r = document.querySelector('input[name="locationType-' + k + '"]:checked');
    return r ? r.value : '';
  }
  function statusOf() {
    var el = $('statusAllToggle');
    return el && el.classList.contains('off') ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
  }
  function locNameVal(k) {
    var el = fieldEl(k, 'locationName');
    return el ? (el.getAttribute('data-value') || '') : '';
  }

  $('copyBtn').addEventListener('click', function () {
    var count = parseInt($('copyCount').value, 10);
    if (!count || count < 1 || count > 10) {
      $('copyError').textContent = '複製するクラス数は1〜10で入力してください';
      return;
    }
    var missing = [];
    for (var k = 1; k <= count; k++) {
      if (!dateVal(k, 'start')) missing.push('複製 ' + k + ' の開始日');
      if (!dateVal(k, 'end')) missing.push('複製 ' + k + ' の終了日');
      if (!typeCode(k)) missing.push('複製 ' + k + ' のロケーション区分');
      if (numVal(k, 'mainTeachers') === '') missing.push('複製 ' + k + ' の予定講師数（メイン）');
      if (numVal(k, 'subTeachers') === '') missing.push('複製 ' + k + ' の予定講師数（サブ）');
    }
    if (missing.length) {
      MessageDialog.required(missing);
      return;
    }
    var relate = !$('relateToSource').classList.contains('off');
    var all = ClassStore.load();
    var created = [];
    for (var n = 1; n <= count; n++) {
      var copy = JSON.parse(JSON.stringify(src));
      copy.id = ClassStore.nextId(all);
      copy.lessonNo = ClassStore.nextLessonNo(all, src.courseCode);
      copy.related = (src.related || []).slice();
      if (relate) {
        created.forEach(function (prev) {
          prev.related = prev.related || [];
          if (copy.lessonNo && prev.related.indexOf(copy.lessonNo) === -1) prev.related.push(copy.lessonNo);
          if (prev.lessonNo && copy.related.indexOf(prev.lessonNo) === -1) copy.related.push(prev.lessonNo);
        });
        if (src.lessonNo && copy.related.indexOf(src.lessonNo) === -1) copy.related.push(src.lessonNo);
        var srcInAll = all.filter(function (r) { return r.id === src.id; })[0];
        if (srcInAll) {
          srcInAll.related = srcInAll.related || [];
          if (copy.lessonNo && srcInAll.related.indexOf(copy.lessonNo) === -1) srcInAll.related.push(copy.lessonNo);
        }
      }
      copy.status = statusOf();
      copy.memo = memoVal(n);
      copy.start = dateVal(n, 'start');
      copy.end = dateVal(n, 'end');
      copy.people = numVal(n, 'people');
      copy.mainTeachers = numVal(n, 'mainTeachers');
      copy.subTeachers = numVal(n, 'subTeachers');
      copy.registMainTeachers = copy.mainTeachers;
      copy.registSubTeachers = copy.subTeachers;
      copy.locationType = typeCode(n);
      copy.locationName = LocationStore.codeOf(locNameVal(n));
      all.push(copy);
      created.push(copy);
    }
    ClassStore.save(all);
    location.href = 'class_list.html';
  });
})();
