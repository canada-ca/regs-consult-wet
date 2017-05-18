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
                if (0 == $(this).index()) { //restrict overlay to column
                    var row = $(this).parent();
                    if ( $(this).hasClass('selected') ) {
                        $(this).removeClass('selected');
                        $( "#document-panel" ).trigger( "close.wb-overlay" );
                    }
                    else {
                        $( "#document-panel" ).trigger( "close.wb-overlay" );
                        $('#comment-table tr.selected').removeClass('selected');

    //                    var idex = row.children().index($(this))
                        if (0 == $(this).index()) { //restrict overlay to column
    //                        console.log($(this).text());
                            $(this).addClass('selected');
//                            var lineno = row.children(':nth-child(3)').text();
                            var sect = row.children(':nth-child(1)').text().split(' ',1); //substr(0,4);
                            var refkey = docid + "-" + sect; // + lineno;
                            var newpart = localStorage.getObject(refkey);
                            if (newpart != null) {
                                $("#docpanelang1").html(newpart["en-CA"]);
                                $("#docpanelang2").html(newpart["fr-CA"]);
                            }
                            $( "#document-panel" ).trigger( "open.wb-overlay" );
                        }
                    }
                } else if (1 == $(this).index()) { //restrict overlay to column
                    var item = $(this);
                    if ( item.hasClass('selected') ) {
                        item.removeClass('selected');
                    }
                    else {
                        item.addClass('selected');
                    }

                }
            } );
            $('.document-ref').on( 'click', function (e) {
                var ref = $(this).attr("data-document-ref")
                if (typeof ref != "undefined") {
                    $( "#document-panel" ).trigger( "close.wb-overlay" );
                    var docid = $("#commentarysummary").attr("data-documentid");
                    var sect = ref.split(' ',1);
                    var refkey = docid + "-" + sect;
                    var newpart = localStorage.getObject(refkey);
                    if (newpart != null) {
                        $("#docpanelang1").html(newpart["en-CA"]);
                        $("#docpanelang2").html(newpart["fr-CA"]);
                    }
                    $( "#document-panel" ).trigger( "open.wb-overlay" );
                }
            } );
            $('.lc').on('click', function (e) {
                var item = $(this).parent('.comment-text');
                if ( item.hasClass('selected') ) {
                    item.removeClass('selected');
                }
                else {
                    item.addClass('selected');
                }
            });

            $('#button').click( function () {
                table.row('.selected').remove().draw( false );
            } );
            $('#commentary-status button').on('click', function (e) {
                var item = $(this);
                item.siblings().each(function( index ) {

                    var cl = $(this).attr("data-selected-class");
                    $(this).removeClass("active");
                    $(this).removeClass(cl);
                    $(this).addClass("btn-default");


                });
                item.addClass("active");
                item.addClass(item.attr("data-selected-class"));

                // Get some values from elements on the comment:
                var det = item.parent('div').attr("data-command");
                if (typeof  det == "undefined") {
                    det = "request";
                }
                var commentaryid =  $("#commentarysummary").attr("data-commentaryid");
                var mySelection = $("#commentary-status button.active").attr("data-status");

                var url = "/receive/commentaries/" + commentaryid + "/" + det + "/";
                // Send the data using post
                var posting = $.ajax({
                type: "POST",
                url: url,
                xhrFields: {
                withCredentials: true
                    },
                    // The key needs to match your method's input parameter (case-sensitive).
                data: JSON.stringify({ "commentary":{
                    "status": mySelection
                    } }),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function(data){
                    //                        interfaceUpdate(data);
                    var overlay = data["commentary"];
                    if (typeof  overlay != "undefined") {
                        $("#cty-status").html(overlay["status"]);
                        //                            $( "#submit-panel" ).trigger( "open.wb-overlay" );
                    }


                },
                error: function(errMsg) {

                }
                    });

                return false;
            });
             $('#comment-table').on( 'click', 'a.delete-note', function (e) {

                return confirm('Are you sure you want to delete this note?');
            });

            getdocument();
            if ($("#notesofotherseditable").length>0) {
                $("#notesofotherseditable textarea.publicnote").each(function(i, el){
                    var simplemdeitem = new SimpleMDE({ element: el,
                    spellChecker: false,
                    forceSync: true,
                    status: false,
                    placeholder: "",
                    });
                    if (!simplemdeitem.isPreviewActive()) {simplemdeitem.togglePreview()};

                });

            }
            if ($("#publicnote").length>0) {

                var postupdatenote = function (){
                    // Get some values from elements on the identity:

                    var noteid = $("#publicnote").attr("data-noteid");

                    var linenum = $("#publicnote").attr("data-linenumber");
                    var notestatus = $("#note-status button.active").attr("data-status");
                    var pubnotetext = simplemdepub.value();
                    if (simplemdepriv !== undefined) {
                        var privnotetext = simplemdepriv.value();
                    }
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
//                        console.log("update success" + JSON.stringify(data));

                    },
                    error: function(errMsg) {
//                        console.log("update fail" + errMsg);
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
                if ($("#privatenote").length>0) {
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
                }
                $(window).on('beforeunload',function(){
//                    console.log(simplemdepub.value());
                    postupdatenote();
                });
                $("#setNoteStatus").on("click",function(){

                    postupdatenote();
                    });
                $("#note-status button").on("click",function(){
                    var item = $(this);
                    item.siblings().each(function( index ) {

                        var cl = $(this).attr("data-selected-class");
                        $(this).removeClass("active");
                        $(this).removeClass(cl);
                        $(this).addClass("btn-default");


                    });
                    item.addClass("active");
                    item.addClass(item.attr("data-selected-class"));
                    postupdatenote();
                });
            }

                }

        init_multifield();

        
    });
