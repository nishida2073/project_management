(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function kindOf() {
    var v = getRadio('taskKind');
    return v ? [v] : [];
  }
  function renderKindRadios() {
    $('kindGroup').innerHTML = TaskTypeStore.load().map(function (it) {
      return '<label class="radio-option"><input type="radio" name="taskKind" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }
  function selectedOf(el) {
    return el.textContent.replace('▾', '').trim();
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function makeChip(value, cls) {
    var chip = document.createElement('span');
    chip.className = 'chip ' + cls;
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    return chip;
  }
  function setCompany(text) {
    var company = $('company');
    company.setAttribute('data-value', text || '');
    company.innerHTML = (text ? esc(text) : '選択してください') + '<span class="caret">▾</span>';
  }
  function refreshAffiliation() {
    var internal = getRadio('affiliation') === '社内';
    $('companyField').style.visibility = internal ? 'hidden' : 'visible';
    if (internal) setCompany('');
  }

  function fill(rec) {
    $('taskId').value = rec.id || '';
    $('taskName').value = rec.name || '';
    $('order').value = rec.order === undefined ? '' : rec.order;
    $('days').value = rec.days === undefined ? '' : rec.days;
    var statusOff = rec.status === '停止中';
    $('statusRow').setAttribute('data-on', '稼働中');
    $('statusRow').setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', statusOff);
    $('statusLabel').textContent = statusOff ? '停止中' : '稼働中';
    checkRadio('taskKind', (rec.kinds || [])[0] || '');
    var internal = rec.company === StaffVenderStore.INTERNAL;
    checkRadio('affiliation', internal ? '社内' : 'パートナー');
    setCompany(internal ? '' : StaffVenderStore.nameOf(rec.company));
    refreshAffiliation();
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    $('company').setAttribute('data-options', StaffVenderStore.activeNames().join(','));
    renderKindRadios();
    var list = TaskStore.load();
    var idx = -1;
    var rec;
    if (editing) {
      var id = new URLSearchParams(location.search).get('id');
      list.forEach(function (t, i) { if (t.id === id) idx = i; });
      if (idx < 0) {
        alert('対象のタスクが見つかりません');
        location.href = 'task_list.html';
        return;
      }
      rec = list[idx];
      $('subLine').textContent = rec.id + '　' + rec.name + 'の情報を編集します';
    } else {
      rec = { id: TaskStore.nextId(list), name: '', kinds: [], order: '', company: StaffVenderStore.INTERNAL, days: '', status: '稼働中' };
    }
    fill(rec);

    Array.prototype.forEach.call(document.querySelectorAll('input[name="affiliation"]'), function (r) {
      r.addEventListener('change', refreshAffiliation);
    });

    $('saveBtn').addEventListener('click', function () {
      var name = $('taskName').value.trim();
      var kinds = kindOf();
      var orderV = $('order').value;
      var affiliation = getRadio('affiliation');
      var companyText = selectedOf($('company'));
      var daysV = $('days').value;
      if (!name || !kinds.length || !affiliation || orderV === '' || daysV === '') {
        alert('必須項目を入力してください');
        return;
      }
      if (affiliation === 'パートナー' && (!companyText || companyText === '選択してください')) {
        alert('実施担当ベンダー名を選択してください');
        return;
      }
      var item = {
        name: name,
        kinds: kinds,
        order: parseInt(orderV, 10),
        company: affiliation === '社内' ? StaffVenderStore.INTERNAL : StaffVenderStore.codeOf(companyText),
        days: parseInt(daysV, 10),
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
      };
      if (editing) {
        list[idx] = Object.assign({ id: rec.id }, item);
      } else {
        list.push(Object.assign({ id: TaskStore.nextId(list) }, item));
      }
      TaskStore.save(list);
      location.href = 'task_list.html';
    });
  }

  window.TaskEditor = { init: init };
})();
