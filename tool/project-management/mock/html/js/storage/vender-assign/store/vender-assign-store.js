(function () {
  var KEY = 'venderAssignList';

  var SEED = [
    {
      classId: 'CLS-001', mainCount: 1, subCount: 1,
      mainVendor: 'VND-001', mainStaff: 'STF-064',
      subs: [{ vendor: 'VND-002', staff: 'STF-068' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationStaff: ''
    }
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED));
    save(seed);
    return seed;
  }

  function blank(classId) {
    return {
      classId: classId, mainCount: 1, subCount: 0,
      mainVendor: '', mainStaff: '', subs: [],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationStaff: ''
    };
  }

  function find(classId) {
    var found = load().filter(function (a) { return a.classId === classId; })[0];
    return found || blank(classId);
  }

  function upsert(record) {
    var list = load().filter(function (a) { return a.classId !== record.classId; });
    list.push(record);
    save(list);
  }

  window.VenderAssignStore = { load: load, save: save, find: find, upsert: upsert, blank: blank };
})();
