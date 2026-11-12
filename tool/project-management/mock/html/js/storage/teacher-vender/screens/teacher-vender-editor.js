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
      rec = { code: '', name: '', tel: '', address: '', memo: '', contactName: '', contactEmail: '', status: '稼働中' };
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
        status: $('statusToggle').classList.contains('off') ? '停止中' : '稼働中'
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
