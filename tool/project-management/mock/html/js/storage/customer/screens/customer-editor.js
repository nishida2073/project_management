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

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = CustomerStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (c, i) { if (c.id === id) idx = i; });
      if (idx < 0) {
        alert('対象の顧客が見つかりません');
        location.href = 'customer_list.html';
        return;
      }
      rec = list[idx];
      $('subLine').textContent = rec.id + '　' + rec.name + 'の情報を編集します';
    } else {
      rec = { id: '', name: '', staff: '', status: '稼働中' };
    }

    $('customerId').textContent = rec.id || '自動採番';
    $('customerName').value = rec.name || '';
    $('staff').value = rec.staff || '';
    var statusOff = rec.status === '停止中';
    $('statusRow').setAttribute('data-on', '稼働中');
    $('statusRow').setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', statusOff);
    $('statusLabel').textContent = statusOff ? '停止中' : '稼働中';

    $('saveBtn').addEventListener('click', function () {
      var v = {
        name: $('customerName').value.trim(),
        staff: $('staff').value.trim(),
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
      };
      if (!v.name) {
        alert('必須項目を入力してください');
        return;
      }
      if (!editing && list.some(function (c) { return c.name === v.name; })) {
        alert('同じ顧客名が既に登録されています');
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ id: rec.id }, v);
      } else {
        list.push(Object.assign({ id: CustomerStore.nextId(list) }, v));
      }
      CustomerStore.save(list);
      location.href = 'customer_list.html';
    });
  }

  window.CustomerEditor = { init: init };
})();
