/*
 * Web Experience Toolkit (WET) / Boîte à outils de l'expérience Web (BOEW)
 * wet-boew.github.io/wet-boew/License-en.html / wet-boew.github.io/wet-boew/Licence-fr.html
 */
;$(document).ready(
    function () {
        "use strict";
        function init_multifield() {
            Storage.prototype.setObject = function (key, value) {
                this.setItem(key, JSON.stringify(value));
            };

            Storage.prototype.getObject = function (key) {
                var value = this.getItem(key);
                return value && JSON.parse(value);
            };
                  var getdocument = function () {

                var docid = $("#commentarysummary").attr("data-documentid");
                if (typeof docid == "undefined") {
                    return;
                }
//                console.log("keys", localStorage.getObject(docid + "-keys"))
                if (localStorage.getObject(docid + "-keys") == null) {
                    var url = "/review/documents/" + docid + "/load/";
                    var jqxhr = $.ajax({
                        type: "GET",
                        url: url,
                        contentType: "application/json; charset=utf-8",
                        dataType: "json",
                        success: function(data) {
                            var comms = data["document"];
                            if (typeof  comms != "undefined") {
                                comms.forEach(function (docitem) {
                                    localStorage.setObject(docitem.key, docitem);
                                });
                            }
                        }
                    });
                }

            }
            var table = $('#comment-table');
            var docid = $("#commentarysummary").attr("data-documentid");
            $('#comment-table').on( 'click', 'tr td', function (e) {
                var row = $(this).parent();
                if ( row.hasClass('selected') ) {
                    row.removeClass('selected');
                    $( "#document-panel" ).trigger( "close.wb-overlay" );
                }
                else {
                    $( "#document-panel" ).trigger( "close.wb-overlay" );
                    $('#comment-table tr.selected').removeClass('selected');
                    row.addClass('selected');
//                    var idex = row.children().index($(this))
                    if (0 == $(this).index()) { //restrict overlay to column
//                        console.log($(this).text());

                        var lineno = row.children(':nth-child(3)').text();
                        var sect = row.children(':nth-child(1)').text().substr(0,4);
                        var refkey = docid + "-" + sect + lineno;
                        var newpart = localStorage.getObject(refkey);
                        if (newpart != null) {
                            $("#docpanelang1").html(newpart["en-CA"]);
                            $("#docpanelang2").html(newpart["fr-CA"]);
                        }
                        $( "#document-panel" ).trigger( "open.wb-overlay" );
                    }
                }
            } );

            $('#button').click( function () {
                table.row('.selected').remove().draw( false );
            } );
            $(document).on("click", "#setStatus", function (e) {
                e.preventDefault();
                // Get some values from elements on the comment:
                var det = $(e.target).attr("data-command");
                if (typeof  det == "undefined") {
                    det = "request";
                }
                var commentaryid =  $("#commentarysummary").attr("data-commentaryid");
                var mySelection = $(e.target).closest("div").find("#commentary-status").find(":selected").val();
                var url = "/receive/commentaries/" + commentaryid + "/" + det + "/";
                // Send the data using post
                var posting = $.ajax({
                    type: "POST",
                    url: url,
                    xhrFields: {
                        withCredentials: true
                    },
                        // The key needs to match your method's input parameter (case-sensitive).
                    data: JSON.stringify({"commentary":{
                        "status": mySelection
                    }}),
                    contentType: "application/json; charset=utf-8",
                    dataType: "json",
                    success: function (data) {
    //                        interfaceUpdate(data);
                        var overlay = data.commentary;
                        if (typeof  overlay != "undefined") {
                            $("#cty-status").find("strong").text(overlay["status"]);
    //                            $( "#submit-panel" ).trigger( "open.wb-overlay" );
                        }

                    },
                    error: function (errMsg) {
                    }
                });
                return false;
                });
            
            getdocument();
            if ($("#publicnote").length>0) {

                var postupdatenote = function (){
                    // Get some values from elements on the identity:

                    var noteid = $("#publicnote").attr("data-noteid");

                    var linenum = $("#publicnote").attr("data-linenumber");
                    var notestatus = $("#note-status").val();
                    var pubnotetext = simplemdepub.value();
                    var privnotetext = simplemdepriv.value();
                    var commentaryid =  $("#commentarysummary").attr("data-commentaryid");
                    var reference = $("#publicnote").attr("data-reference");
                    var noteobj  = new Object();
                    if (noteid !== undefined) { noteobj["id"] = noteid }
                    if (notestatus !== undefined) { noteobj["status"] = notestatus }
                    if (linenum !== undefined) { noteobj["linenumber"] = linenum }
                    if (pubnotetext !== undefined) { noteobj["textshared"] = pubnotetext }
                    if (privnotetext !== undefined) { noteobj["textuser"] = privnotetext }
                    if (commentaryid !== undefined) { noteobj["commentaryid"] = commentaryid }
                    if (reference !== undefined) { noteobj["reference"] = reference }

                    var docid =  $("#commentarysummary").attr("data-documentid");
                    var url = "/analyze/documents/" + docid + "/notes/";
                    // Send the data using post
                    var posting = $.ajax({
                    type: "POST",
                    url: url,
                    xhrFields: {
                    withCredentials: true
                        },
                        // The key needs to match your method's input parameter (case-sensitive).
                    data: JSON.stringify({ "notes":[
                        noteobj
                        ]
                        }),
                    contentType: "application/json; charset=utf-8",
                    dataType: "json",
                    success: function(data){
                        console.log("update success" + JSON.stringify(data));

                    },
                    error: function(errMsg) {
                        console.log("update fail" + errMsg);
                    }
                        });
                    
                }
                var simplemdepub = new SimpleMDE({ element: $("#publicnote")[0],
                spellChecker: false,
                forceSync: true,
//                autosave: {
//                enabled: true,
//                uniqueId: "Public-Note",
//                delay: 10000,
//                    },
                placeholder: "Type notes that will be seen by other users.",
                    });
                simplemdepub.render();
                        simplemdepub.codemirror.on("blur", function(){
                            console.log(simplemdepub.value());
                            postupdatenote();
                        });
                var simplemdepriv = new SimpleMDE({ element: $("#privatenote")[0],
                spellChecker: false,
                forceSync: true,
//                autosave: {
//                enabled: true,
//                uniqueId: "Private-Note",
//                delay: 10000,
//                    },
                placeholder: "Type notes that will only be seen by you.",
                    });
                simplemdepriv.render();
                simplemdepriv.codemirror.on("blur", function(){
                    console.log(simplemdepub.value());
                    postupdatenote();
                });
                $(window).unload(function(){
                    console.log(simplemdepub.value());
                    postupdatenote();
                });

            }

                }

        init_multifield();

        
    });
