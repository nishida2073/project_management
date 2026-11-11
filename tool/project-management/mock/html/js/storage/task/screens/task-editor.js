(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function kindsOf(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (c) {
      var name = c.textContent.replace('✕', '').trim();
      var found = TaskKindStore.load().filter(function (t) { return t.name === name; })[0];
      return found ? found.code : name;
    });
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
  function fill(rec) {
    $('taskId').value = rec.id || '';
    $('taskName').value = rec.name || '';
    $('order').value = rec.order === undefined ? '' : rec.order;
    $('days').value = rec.days === undefined ? '' : rec.days;
    var box = $('kindBox');
    var addBtn = box.querySelector('.chip-add');
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (rec.kinds || []).forEach(function (k) {
      box.insertBefore(makeChip(TaskKindStore.nameOf(k), TaskKindStore.colorOf(k)), addBtn);
    });
    var company = $('company');
    company.setAttribute('data-value', VendorStore.nameOf(rec.company));
    company.innerHTML = (rec.company ? esc(VendorStore.nameOf(rec.company)) : '選択してください') + '<span class="caret">▾</span>';
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    document.getElementById('company').setAttribute('data-options', ['社内'].concat(VendorStore.activeNames()).join(','));
    var kinds = TaskKindStore.load();
    var kindBox = $('kindBox');
    kindBox.setAttribute('data-options', kinds.map(function (k) { return k.name; }).join(','));
    kindBox.setAttribute('data-chip-map', JSON.stringify(kinds.reduce(function (m, k) { m[k.name] = k.color; return m; }, {})));
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
      rec = { id: TaskStore.nextId(list), name: '', kinds: [], order: '', company: '', days: '' };
    }
    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var name = $('taskName').value.trim();
      var kinds = kindsOf($('kindBox'));
      var orderV = $('order').value;
      var company = selectedOf($('company'));
      var daysV = $('days').value;
      if (!name || !kinds.length || orderV === '' || !company || company === '選択してください' || daysV === '') {
        alert('必須項目を入力してください');
        return;
      }
      var item = {
        name: name,
        kinds: kinds,
        order: parseInt(orderV, 10),
        company: VendorStore.codeOf(company),
        days: parseInt(daysV, 10)
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
