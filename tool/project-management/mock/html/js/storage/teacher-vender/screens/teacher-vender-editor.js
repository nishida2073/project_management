(function () {
  function setToggle(off) {
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.labelOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.labelOf('STOPPED'));
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.labelOf('STOPPED') : OperatingStatusStore.labelOf('ACTIVE');
  }

  function fill(rec) {
    $('vendorCode').textContent = rec.code || '自動採番';
    $('vendorName').value = rec.name || '';
    $('tel').value = rec.tel || '';
    $('address').value = rec.address || '';
    $('memo').value = rec.memo || '';
    $('contactName').value = rec.contactName || '';
    $('contactEmail').value = rec.contactEmail || '';
    setToggle(rec.status === OperatingStatusStore.labelOf('STOPPED'));
  }

  function renderRadios(group, name, items) {
    group.innerHTML = items.map(function (it) {
      return '<label class="radio-option"><input type="radio" name="' + name + '" value="' + it.code + '"><span class="radio-dot"></span><span class="tag ' + it.color + '">' + it.name + '</span></label>';
    }).join('');
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = TeacherVenderStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (v, i) { if (v.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象の講師ベンダーが見つかりません', function () { location.href = 'teacher_vender_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', name: '', tel: '', address: '', memo: '', contactName: '', contactEmail: '', status: OperatingStatusStore.labelOf('ACTIVE') };
    }

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = {
        name: $('vendorName').value.trim(),
        tel: $('tel').value.trim(),
        address: $('address').value.trim(),
        memo: $('memo').value,
        contactName: $('contactName').value.trim(),
        contactEmail: $('contactEmail').value.trim(),
        status: readStatus()
      };
      var missing = [];
        if (!v.name) missing.push('講師ベンダー名');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: TeacherVenderStore.nextCode(list) }, v));
      }
      TeacherVenderStore.save(list);
      location.href = 'teacher_vender_list.html';
    });
  }

  window.VendorEditor = { init: init };
})();
