(function () {
  var KEY = 'venderAssignList';

  var SEED = [
    {
      classId: 'CLS-001', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-001', staff: 'STF-064' }],
      subs: [{ vendor: 'TCV-002', staff: 'STF-068' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationStaff: ''
    }
    ,
    {
      classId: 'CLS-005', mainCount: 1, subCount: 2,
      mains: [{ vendor: 'TCV-003', staff: 'STF-066' }],
      subs: [{ vendor: 'TCV-004', staff: 'STF-067' }, { vendor: 'TCV-005', staff: 'STF-073' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationStaff: ''
    }
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function staffText(v) {
    if (typeof v === 'string' && /^STF-/.test(v) && window.StaffStore) return StaffStore.nameOf(v) || v;
    if (typeof v === 'string' && /^TCV-/.test(v) && window.TeacherVenderStore) return TeacherVenderStore.nameOf(v) || v;
    return v || '';
  }

  function normalize(a) {
    if (!a.mains) {
      a.mains = (a.mainVendor || a.mainStaff) ? [{ vendor: a.mainVendor || '', staff: a.mainStaff || '' }] : [];
    }
    delete a.mainVendor;
    delete a.mainStaff;
    a.subs = a.subs || [];
    ['attendeeVendor', 'attendee', 'motivationVendor', 'motivationStaff'].forEach(function (k) { a[k] = staffText(a[k]); });
    a.mains = a.mains.map(function (m) { return { vendor: m.vendor, staff: staffText(m.staff) }; });
    a.subs = a.subs.map(function (s) { return { vendor: s.vendor, staff: staffText(s.staff) }; });
    return a;
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw).map(normalize);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED)).map(normalize);
    save(seed);
    return seed;
  }

  function blank(classId) {
    return {
      classId: classId, mainCount: 1, subCount: 0,
      mains: [], subs: [],
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
