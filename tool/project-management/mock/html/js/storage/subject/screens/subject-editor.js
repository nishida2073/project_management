(function () {
  function $(id) { return document.getElementById(id); }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }

  function fill(rec) {
    var codeEl = $('subjectCode');
    if (codeEl.tagName === 'INPUT') codeEl.value = rec.code || '';
    else codeEl.textContent = rec.code;
    checkRadio('subjectType', rec.type || 'ST-02');
    $('subjectName').value = rec.name || '';
    var off = rec.status === '停止中';
    var row = $('statusRow');
    row.setAttribute('data-on', '稼働中');
    row.setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', off);
    $('statusLabel').textContent = off ? '停止中' : '稼働中';
  }

  function read() {
    return {
      type: getRadio('subjectType'),
      name: $('subjectName').value.trim(),
      status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
    };
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = SubjectStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (s, i) { if (s.code === id) idx = i; });
      if (idx < 0) {
        alert('対象の科目が見つかりません');
        location.href = 'subject_list.html';
        return;
      }
      rec = list[idx];
      $('subLine').textContent = rec.code + '　' + rec.name + 'の情報を編集します';
    } else {
      rec = { code: '', type: 'ST-02', name: '', status: '稼働中' };
    }

    renderRadios(document.getElementById('subjectTypeGroup'), 'subjectType', SubjectTypeStore.load());

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = read();
      if (!v.type || !v.name) {
        alert('必須項目を入力してください');
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        var code = $('subjectCode').value.trim().toUpperCase();
        if (!SubjectStore.isValidCode(code)) {
          alert('科目コードは英字2文字＋数字2桁で入力してください（例：BC02）');
          return;
        }
        if (list.some(function (s) { return s.code === code; })) {
          alert('同じ科目コードが既に登録されています');
          return;
        }
        list.push(Object.assign({ code: code }, v));
      }
      SubjectStore.save(list);
      location.href = 'subject_list.html';
    });
  }

  window.SubjectEditor = { init: init };
})();
