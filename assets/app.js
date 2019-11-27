function add_addr_field(id, destClass) {

    var addrElement = $( "." + id ).last();
    addrElement.clone().appendTo( "#" + destClass);

    $('.' + id + ' .btn').first().remove();

    return false;
}

function get_commands_from_object(objectName) {
    var postForm = {
        object: objectName
    };
    $.ajax({
        type      : 'POST',
        url       : 'get_commands_from_object',
        data      : postForm,
        success   : function(data) {
            $('#command_select').html(data);
            get_command_form($("select[name='command']").val());
        }
    });
}

function get_command_form(command) {
    var postForm = {
        object : $('#object_select').val(),
        command: command
    };
    $.ajax({
        type      : 'POST',
        url       : 'get_command_form',
        data      : postForm,
        success   : function(data) {
            $('#command_form').html(data);
        }
    });
}

$(document).ready(function(){

    $('a[data-toggle="tab"]').on('shown.bs.tab', function (e) {
        if(e.target.hash === '#login_xml') {

            var formData = $('#login_form_data').serialize();

            $.ajax({
                type      : 'POST',
                url       : 'get_login_xml',
                data      : formData,
                success   : function(data) {
                    var login_xml_pre = $('#login_xml_code');
                    login_xml_pre.html(data);
                    Prism.highlightAll();
                }
            });

        }

        if(e.target.hash === '#request_xml') {

            var formData = $('#execute_form').serialize();

            $.ajax({
                type      : 'POST',
                url       : 'get_request_xml',
                data      : formData,
                success   : function(data) {
                    var request_xml_pre = $('#request_xml_code');
                    request_xml_pre.html(data);
                    Prism.highlightAll();
                }
            });

        }

    });
});
