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
            $('#comment-table').on( 'click', 'tr', function (e) {
                if ( $(this).hasClass('selected') ) {
                    $(this).removeClass('selected');
                    $( "#document-panel" ).trigger( "close.wb-overlay" );
                }
                else {
                    $( "#document-panel" ).trigger( "close.wb-overlay" );
                    $('#comment-table tr.selected').removeClass('selected');
                    $(this).addClass('selected');

                    var lineno = $(this).children(':nth-child(1)').text();
                    var sect = $(this).children(':nth-child(2)').text().substr(0,4);
                    var refkey = docid + "-" + sect + lineno;
                    var newpart = localStorage.getObject(refkey);
                    if (newpart != null) {
                        $("#docpanelang1").html(newpart["en-CA"]);
                        $("#docpanelang2").html(newpart["fr-CA"]);
                    }
                    $( "#document-panel" ).trigger( "open.wb-overlay" );
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
        }

        init_multifield();

        
    });
