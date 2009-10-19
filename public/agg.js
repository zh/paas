function showStuff() {
  var req = new XMLHttpRequest();
  req.open("GET", "/json", true);
  req.onreadystatechange = function() {
    if (req.readyState != 4) {
      return;
    }
    gotStuff(req.status, req.responseText);
  };
  req.send(null);
}

function gotStuff(status, text) {
  if (status != 200) {
    window.setTimeout(showStuff, 5000);
    return;
  }

  var content = "";
  var items = eval(text);
  if (items.length == 0) {
    content = "Nothing yet.\n"
  } else {
    content += "<ul>\n";	  
    for (var i = 0; i < items.length; ++i) {
      content += '<li>'
      content += '<img src="/images/' + items[i].status + '.png" title="' + 
                 items[i].status + '" />';
      content += '<big><a href="/user/' + items[i].nick + '">' + 
                 items[i].nick + '</a></big>: ';
      if (items[i].message != '') {
        content += ' (' + items[i].message + ')';
      }
      content += ' <small title="' + items[i].time  + 
                 '">' + items[i].since + " ago</small></li>\n";
    }
    content += "</ul>\n";	  
  }

  document.getElementById("entries").innerHTML = content;
  window.setTimeout(showStuff, 5000);
}

window.onload = showStuff;
