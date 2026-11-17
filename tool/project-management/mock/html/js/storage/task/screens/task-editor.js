(function () {
  function kindOf() {
    var v = getRadio('taskKind');
    return v ? [v] : [];
  }
  function renderWorkRadios() {
    $('workGroup').innerHTML = WorkTypeStore.load().map(function (it) {
      return '<label class="radio-option"><input type="radio" name="workType" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }
  function renderKindRadios() {
    $('kindGroup').innerHTML = TaskTypeStore.load().map(function (it) {
      return '<label class="radio-option"><input type="radio" name="taskKind" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }
  function selectedOf(el) {
    return el.textContent.replace('▾', '').trim();
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
    var internal = getRadio('affiliation') === AffiliationStore.nameOf('INTERNAL');
    $('companyField').style.visibility = internal ? 'hidden' : 'visible';
    if (internal) setCompany('');
  }

  function fill(rec) {
    $('taskId').textContent = rec.id || '自動採番';
    $('taskName').value = rec.name || '';
    $('order').value = rec.order === undefined ? '' : rec.order;
    $('days').value = rec.days === undefined ? '' : rec.days;
    var statusOff = rec.status === OperatingStatusStore.nameOf('STOPPED');
    $('statusRow').setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    $('statusRow').setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    setStatusOff(statusOff);
    $('statusLabel').textContent = statusOff ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
    checkRadio('taskKind', (rec.kinds || [])[0] || '');
    checkRadio('workType', rec.workType || '');
    $('memo').value = rec.memo || '';
    var internal = rec.company === StaffVenderStore.INTERNAL;
    checkRadio('affiliation', internal ? AffiliationStore.nameOf('INTERNAL') : AffiliationStore.nameOf('PARTNER'));
    setCompany(internal ? '' : StaffVenderStore.nameOf(rec.company));
    refreshAffiliation();
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    $('company').setAttribute('data-options', StaffVenderStore.activeNames().join(','));
    renderKindRadios();
    renderWorkRadios();
    var list = TaskStore.load();
    var idx = -1;
    var rec;
    if (editing) {
      var id = new URLSearchParams(location.search).get('id');
      list.forEach(function (t, i) { if (t.id === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象のタスクが見つかりません', function () { location.href = 'task_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { id: '', name: '', kinds: [], order: '', company: StaffVenderStore.INTERNAL, days: '', workType: '', status: OperatingStatusStore.nameOf('ACTIVE') };
    }
    fill(rec);

    Array.prototype.forEach.call(document.querySelectorAll('input[name="affiliation"]'), function (r) {
      r.addEventListener('change', refreshAffiliation);
    });

    $('saveBtn').addEventListener('click', function () {
      var name = $('taskName').value.trim();
      var kinds = kindOf();
      var workType = getRadio('workType');
      var orderV = $('order').value;
      var affiliation = getRadio('affiliation');
      var companyText = selectedOf($('company'));
      var daysV = $('days').value;
      var missing = [];
        if (!name) missing.push('タスク名');
        if (!kinds.length) missing.push('タスク区分');
        if (!workType) missing.push('作業区分');
        if (!affiliation) missing.push('実務担当区分');
        if (orderV === '') missing.push('作業順');
        if (daysV === '') missing.push('予定開始日数');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (affiliation === AffiliationStore.nameOf('PARTNER') && (!companyText || companyText === '選択してください')) {
        MessageDialog.required(['実施担当ベンダー']);
        return;
      }
      var item = {
        name: name,
        kinds: kinds,
        order: parseInt(orderV, 10),
        company: affiliation === AffiliationStore.nameOf('INTERNAL') ? StaffVenderStore.INTERNAL : StaffVenderStore.codeOf(companyText),
        days: parseInt(daysV, 10),
        workType: workType,
        memo: $('memo').value,
        status: readStatus()
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
