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
    $('locationCode').textContent = rec.code || '自動採番';
    checkRadio('locationType', rec.type || 'LT-01');
    $('locationName').value = rec.name || '';
    $('tel').value = rec.tel || '';
    $('address').value = rec.address || '';
    var off = rec.status === '停止中';
    var row = $('statusRow');
    row.setAttribute('data-on', '稼働中');
    row.setAttribute('data-off', '停止中');
    $('statusToggle').classList.toggle('off', off);
    $('statusLabel').textContent = off ? '停止中' : '稼働中';
  }

  function read() {
    return {
      type: getRadio('locationType'),
      name: $('locationName').value.trim(),
      tel: $('tel').value.trim(),
      address: $('address').value.trim(),
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
    var list = LocationStore.load();
    var id = new URLSearchParams(location.search).get('id');
    var idx = -1;
    var rec;

    if (editing) {
      list.forEach(function (l, i) { if (l.code === id) idx = i; });
      if (idx < 0) {
        alert('対象のロケーションが見つかりません');
        location.href = 'location_list.html';
        return;
      }
      rec = list[idx];
      $('subLine').textContent = rec.code + '　' + rec.name + 'の情報を編集します';
    } else {
      rec = { code: '', type: 'LT-01', name: '', tel: '', address: '', status: '稼働中' };
    }

    renderRadios(document.getElementById('locationTypeGroup'), 'locationType', LocationTypeStore.load());

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
        list.push(Object.assign({ code: LocationStore.nextCode(list) }, v));
      }
      LocationStore.save(list);
      location.href = 'location_list.html';
    });
  }

  window.LocationEditor = { init: init };
})();
