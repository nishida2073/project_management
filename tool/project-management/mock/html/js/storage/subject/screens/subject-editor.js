(function () {

  function addVersionChip(value) {
    var box = $('subjectVersions');
    var chip = document.createElement('span');
    chip.className = 'chip tag-like blue';
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    box.insertBefore(chip, box.querySelector('.chip-add'));
  }

  function versionValues() {
    return Array.prototype.map.call($('subjectVersions').querySelectorAll('.chip'), function (c) {
      return c.textContent.replace('✕', '').trim();
    });
  }

  function fill(rec) {
    var codeEl = $('subjectCode');
    if (codeEl.tagName === 'INPUT') codeEl.value = rec.code || '';
    else codeEl.textContent = rec.code;
    checkRadio('subjectType', rec.type || '');
    var box = $('subjectVersions');
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (rec.versions || []).forEach(function (v) { addVersionChip(v); });
    $('subjectName').value = rec.name || '';
    $('memo').value = rec.memo || '';
    var off = rec.status === OperatingStatusStore.nameOf('STOPPED');
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
  }

  function read() {
    return {
      type: getRadio('subjectType'),
      name: $('subjectName').value.trim(),
      versions: versionValues(),
      memo: $('memo').value,
      status: readStatus()
    };
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + tagClassOf(name) + ' ' + it.color + '">' + it.name + '</span></label>';
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
        MessageDialog.show('対象の科目が見つかりません', function () { location.href = 'subject_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', type: '', name: '', versions: ['1.0'], status: OperatingStatusStore.nameOf('ACTIVE') };
    }

    renderRadios(document.getElementById('subjectTypeGroup'), 'subjectType', SubjectTypeStore.load());

    fill(rec);

    $('subjectVersions').querySelector('.chip-add').addEventListener('click', function () {
      InputDialog.open({
        title: '版を追加',
        label: '版',
        placeholder: '例）1.2',
        validate: function (value) {
          if (!value) return '版を入力してください';
          if (versionValues().indexOf(value) !== -1) return '同じ版が既に登録されています';
          return '';
        }
      }).then(function (value) {
        if (value) addVersionChip(value);
      });
    });

    $('saveBtn').addEventListener('click', function () {
      var v = read();
      var missing = [];
        if (!v.type) missing.push('科目区分');
        if (!v.name) missing.push('科目名');
        if (!v.versions.length) missing.push('版');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        var code = $('subjectCode').value.trim().toUpperCase();
        if (!SubjectStore.isValidCode(code)) {
          MessageDialog.show('科目コードは英字2文字＋数字2桁で入力してください（例：BC02）');
          return;
        }
        if (list.some(function (s) { return s.code === code; })) {
          MessageDialog.show('同じ科目コードが既に登録されています');
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
