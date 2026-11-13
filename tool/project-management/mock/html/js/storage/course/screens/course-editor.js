(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  function setSelect(el, value) {
    var v = value || '';
    el.setAttribute('data-value', v);
    el.innerHTML = (v ? esc(v) : '選択してください') + '<span class="caret">▾</span>';
  }
  function getSelect(el) {
    var v = ownText(el);
    return v === '選択してください' ? '' : v;
  }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function monthInputs() {
    return Array.prototype.slice.call(document.querySelectorAll('.month-grid input'));
  }

  function renderGroup(name, items) {
    var group = document.querySelector('input[name="' + name + '"]').closest('.radio-group');
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function refreshSubject() {
    var s = SubjectStore.find(SubjectStore.codeOf(getSelect($('subjectSelect'))));
    $('subjectCode').textContent = s ? s.code : '';
    $('subjectType').textContent = s ? SubjectTypeStore.nameOf(s.type) : '';
    $('subjectType').className = 'tag ' + (s ? SubjectTypeStore.colorOf(s.type) : '');
  }

  function refreshAnnual() {
    var total = monthInputs().reduce(function (a, i) { return a + (parseInt(i.value, 10) || 0); }, 0);
    $('annualClassCount').textContent = total + 'クラス';
  }

  var nameEdited = false;
  var isEditing = false;

  function autoName() {
    var p = document.querySelector('input[name="participationType"]:checked');
    var part = p ? ParticipationTypeStore.nameOf(p.value) : '';
    var subject = getSelect($('subjectSelect'));
    if (!isEditing) {
      var subjectCode = SubjectStore.codeOf(subject);
      var suffix = part === '受託' ? 'B' : (part === '公募' ? 'A' : '');
      $('courseCode').value = (subjectCode && suffix) ? (subjectCode + suffix) : '';
    }
    if (nameEdited) return;
    $('courseName').value = (part && subject) ? (part + '_' + subject) : '';
  }

  function fill(rec, editing) {
    setSelect($('subjectSelect'), SubjectStore.nameOf(rec.subject));
    setSelect($('courseYear'), rec.year);
    $('courseCode').value = rec.code || '';
    $('courseCode').disabled = true;
    $('courseCode').classList.add('readonly');
    checkRadio('participationType', rec.part || '');
    $('courseName').value = rec.name || '';
    checkRadio('deliveryType', rec.delivery || '');
    $('days').querySelector('input').value = rec.days === undefined ? '' : rec.days;
    $('minPeople').querySelector('input').value = rec.min === undefined ? '' : rec.min;
    $('maxPeople').querySelector('input').value = rec.max === undefined ? '' : rec.max;
    var inputs = monthInputs();
    inputs.forEach(function (i, idx) { i.value = (rec.monthly && rec.monthly[idx]) || 0; });
    $('memo').value = rec.memo || '';
    var row = $('statusRow');
    row.setAttribute('data-on', '稼働中');
    row.setAttribute('data-off', '停止中');
    var off = rec.status === '停止中';
    $('statusToggle').classList.toggle('off', off);
    $('statusLabel').textContent = off ? '停止中' : '稼働中';
    refreshSubject();
    refreshAnnual();
  }

  function read() {
    var off = $('statusToggle').classList.contains('off');
    return {
      year: getSelect($('courseYear')),
      code: $('courseCode').value.trim(),
      subject: SubjectStore.codeOf(getSelect($('subjectSelect'))),
      part: getRadio('participationType'),
      name: $('courseName').value.trim(),
      delivery: getRadio('deliveryType'),
      days: $('days').querySelector('input').value.trim(),
      min: $('minPeople').querySelector('input').value.trim(),
      max: $('maxPeople').querySelector('input').value.trim(),
      monthly: monthInputs().map(function (i) { return parseInt(i.value, 10) || 0; }),
      memo: $('memo').value,
      status: off ? '停止中' : '稼働中'
    };
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    isEditing = editing;
    $('subjectSelect').setAttribute('data-options', SubjectStore.activeNames().join(','));
    renderGroup('participationType', ParticipationTypeStore.load());
    if (editing) {
      document.querySelector('input[name="participationType"]').closest('.radio-group').style.opacity = '0.6';
      document.querySelectorAll('input[name="participationType"]').forEach(function (r) { r.disabled = true; });
    }
    renderGroup('deliveryType', DeliveryTypeStore.load());
    var list = CourseStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (c, i) { if (c.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象のコースが見つかりません', function () { location.href = 'course_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { year: '2026', subject: '', part: '', name: '', delivery: '', days: '', min: '', max: '', monthly: [], status: '稼働中', code: '' };
    }

    fill(rec, editing);

    $('courseName').addEventListener('input', function () { nameEdited = true; });
    document.querySelectorAll('input[name="participationType"]').forEach(function (r) { r.addEventListener('change', autoName); });
    new MutationObserver(function () { refreshSubject(); autoName(); }).observe($('subjectSelect'), { attributes: true, attributeFilter: ['data-value'] });
    document.querySelector('.month-grid').addEventListener('input', refreshAnnual);
    document.addEventListener('click', function () { setTimeout(refreshAnnual, 0); }, true);

    $('saveBtn').addEventListener('click', function () {
      var v = read();
      var missing = [];
        if (!v.code) missing.push('コースコード');
        if (!v.year) missing.push('年度');
        if (!v.subject) missing.push('科目名');
        if (!v.part) missing.push('参加区分');
        if (!v.name) missing.push('コース名');
        if (!v.delivery) missing.push('実施形態');
        if (v.days === '') missing.push('日数');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (!editing && list.some(function (c) { return c.code === v.code; })) {
        MessageDialog.show('同じコースコードが既に登録されています');
        return;
      }
      var item = {
        code: v.code, year: v.year, subject: v.subject, part: v.part,
        name: v.name, delivery: v.delivery, days: parseInt(v.days, 10), min: v.min === '' ? '' : parseInt(v.min, 10),
        max: v.max === '' ? '' : parseInt(v.max, 10), status: v.status, monthly: v.monthly,
        actual: editing ? list[idx].actual : 0,
        memo: v.memo
      };
      if (editing) {
        list[idx] = item;
      } else {
        list.push(item);
      }
      CourseStore.save(list);
      location.href = 'course_list.html';
    });
  }

  window.CourseEditor = { init: init };
})();
