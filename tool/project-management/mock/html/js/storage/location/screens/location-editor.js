(function () {

  function fill(rec) {
    $('locationCode').textContent = rec.code || '自動採番';
    checkRadio('locationType', rec.type || '');
    $('locationName').value = rec.name || '';
    $('tel').value = rec.tel || '';
    $('address').value = rec.address || '';
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
      type: getRadio('locationType'),
      name: $('locationName').value.trim(),
      tel: $('tel').value.trim(),
      address: $('address').value.trim(),
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
    var list = LocationStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (l, i) { if (l.code === id) idx = i; });
      if (idx < 0) {
        MessageDialog.show('対象のロケーションが見つかりません', function () { location.href = 'location_list.html'; });
        return;
      }
      rec = list[idx];
    } else {
      rec = { code: '', type: '', name: '', tel: '', address: '', status: OperatingStatusStore.nameOf('ACTIVE') };
    }

    renderRadios(document.getElementById('locationTypeGroup'), 'locationType', LocationTypeStore.load());

    fill(rec);

    $('saveBtn').addEventListener('click', function () {
      var v = read();
      var missing = [];
        if (!v.type) missing.push('ロケーション区分');
        if (!v.name) missing.push('ロケーション名');
      if (missing.length) {
        MessageDialog.required(missing);
        return;
      }
      if (editing) {
        list[idx] = Object.assign({ code: rec.code }, v);
      } else {
        list.push(Object.assign({ code: LocationStore.nextCode(list) }, v));
      }
      LocationStore.save(list);
      location.href = 'location_list.html';
    });
  }

  window.LocationEditor = { init: init };
})();
