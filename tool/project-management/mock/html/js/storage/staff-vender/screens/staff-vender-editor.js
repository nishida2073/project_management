(function () {

  function setToggle(off) {
    var row = $('statusRow');
    row.setAttribute('data-on', OperatingStatusStore.nameOf('ACTIVE'));
    row.setAttribute('data-off', OperatingStatusStore.nameOf('STOPPED'));
    setStatusOff(off);
    $('statusLabel').textContent = off ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE');
  }

  function fill(rec) {
    $('staffVenderCode').textContent = rec.code || '自動採番';
    $('staffVenderName').value = rec.name || '';
    $('tel').value = rec.tel || '';
    $('address').value = rec.address || '';
    $('memo').value = rec.memo || '';
    $('contactName').value = rec.contactName || '';
    $('contactEmail').value = rec.contactEmail || '';
    setToggle(rec.status === OperatingStatusStore.nameOf('STOPPED'));
  }

  function init(opts) {
    var editing = opts.mode === 'edit';
    var list = StaffVenderStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (c, i) { if (c.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象の実施担当ベンダーが見つかりません', function () { location.href = 'staff_vender_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', name: '', tel: '', address: '', memo: '', contactName: '', contactEmail: '', status: OperatingStatusStore.nameOf('ACTIVE') };
    }

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = {
        name: $('staffVenderName').value.trim(),
        tel: $('tel').value.trim(),
        address: $('address').value.trim(),
        memo: $('memo').value,
        contactName: $('contactName').value.trim(),
        contactEmail: $('contactEmail').value.trim(),
        status: readStatus()
      };
      var missing = [];
        if (!v.name) missing.push('実施担当ベンダー名');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: StaffVenderStore.nextCode(list) }, v));
      }
      StaffVenderStore.save(list);
      location.href = 'staff_vender_list.html';
    });
  }

  window.StaffVenderEditor = { init: init };
})();
