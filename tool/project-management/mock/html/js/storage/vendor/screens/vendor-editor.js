(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function checkRadio(name, value) {
    var r = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
    if (r) r.checked = true;
  }
  function getRadio(name) {
    var r = document.querySelector('input[name="' + name + '"]:checked');
    return r ? r.value : '';
  }
  function makeChip(value) {
    var chip = document.createElement('span');
    chip.className = 'chip y' + value.replace(/[^0-9]/g, '');
    chip.appendChild(document.createTextNode(value + ' '));
    var x = document.createElement('x');
    x.textContent = '✕';
    x.addEventListener('click', function (e) { e.stopPropagation(); chip.remove(); });
    chip.appendChild(x);
    return chip;
  }
  function yearsOf(box) {
    return Array.prototype.map.call(box.querySelectorAll('.chip'), function (c) {
      return c.textContent.replace('✕', '').trim();
    });
  }
  function setToggle(off) {
    var row = $('statusRow');
    row.setAttribute('data-on', '稼働中');
    row.setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', off);
    $('statusLabel').textContent = off ? '停止中' : '稼働中';
  }

  function fill(rec) {
    $('vendorCode').textContent = rec.code || '自動採番';
    $('vendorName').value = rec.name || '';
    checkRadio('contractType', rec.contract || 'CT-01');
    var box = $('yearBox');
    var addBtn = box.querySelector('.chip-add');
    box.querySelectorAll('.chip').forEach(function (c) { c.remove(); });
    (rec.years || []).forEach(function (y) { box.insertBefore(makeChip(y), addBtn); });
    $('tel').value = rec.tel || '';
    $('address').value = rec.address || '';
    $('memo').value = rec.memo || '';
    $('contactName').value = rec.contactName || '';
    $('contactEmail').value = rec.contactEmail || '';
    setToggle(rec.status === '停止中');
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = VendorStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (v, i) { if (v.code === id) idx = i; });
      if (idx < 0) {
        alert('対象の講師ベンダーが見つかりません');
        location.href = 'vendor_list.html';
        return;
      }
      rec = list[idx];
      $('subLine').textContent = rec.code + '　' + rec.name + 'の情報を編集します';
    } else {
      rec = { code: '', name: '', contract: 'CT-01', years: [], tel: '', address: '', memo: '', contactName: '', contactEmail: '', status: '稼働中' };
    }
    renderRadios(document.getElementById('contractGroup'), 'contractType', ContractTypeStore.load());

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = {
        name: $('vendorName').value.trim(),
        contract: getRadio('contractType'),
        years: yearsOf($('yearBox')),
        tel: $('tel').value.trim(),
        address: $('address').value.trim(),
        memo: $('memo').value,
        contactName: $('contactName').value.trim(),
        contactEmail: $('contactEmail').value.trim(),
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
      };
      if (!v.name || !v.contract || !v.years.length) {
        alert('必須項目を入力してください');
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: VendorStore.nextCode(list) }, v));
      }
      VendorStore.save(list);
      location.href = 'vendor_list.html';
    });
  }

  window.VendorEditor = { init: init };
})();
