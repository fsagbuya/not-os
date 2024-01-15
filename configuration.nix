{ pkgs, ... }:

{
  imports = [ ./qemu.nix ];
  not-os.nix = true;
  environment.systemPackages = [ pkgs.utillinux ];
  environment.etc = {
    "ssh/authorized_keys.d/root" = {
      text = ''
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBNdIiLvP2hmDUFyyE0oLOIXrjrMdWWpBV9/gPR5m4AiARx4JkufIDZzmptdYQ5FhJORJ4lluPqp7dAmahoSwg4lv9Di0iNQpHMJvNGZLHYKM1H1FWCCFIEDJ8bD4SVfrDg== root
        ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCMALVC8RDTHec+PC8y1s3tcpUAODgq6DEzQdHDf/cyvDMfmCaPiMxfIdmkns5lMa03hymIfSmLUF0jFFDc7biRp7uf9AAXNsrTmplHii0l0McuOOZGlSdZM4eL817P7UwJqFMxJyFXDjkubhQiX6kp25Kfuj/zLnupRCaiDvE7ho/xay6Jrv0XLz935TPDwkc7W1asLIvsZLheB+sRz9SMOb9gtrvk5WXZl5JTOFOLu+JaRwQLHL/xdcHJTOod7tqHYfpoC5JHrEwKzbhTOwxZBQBfTQjQktKENQtBxXHTe71rUEWfEZQGg60/BC4BrRmh4qJjlJu3v4VIhC7SSHn1 root
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBF/YybP+fQ0J+bNqM5Vgx5vDmVqVWsgUdF1moUxghv7d73GZAFaM6IFBdrXTAa33AwnWwDPMrTgP1V6SXBkb3ciJo/lD1urJGbydbSI5Ksq9d59wvOeANvyWYrQw6+eqTQ== sb
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBFkmOCQ3BQh3qUjLtfdqyeBsx8rkk/QYlzB0TMrnfn6waLN6yKfPC3WVFv4zN5kNKb/OayvqDa+zfkKe85e/oIPQQKflF7GrCHdssz33DCnW90cz532E6iqG1pjeZjID2A== flo
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBPsv4UMEFV0UHeHdA9R3sC+qoMxrqhcuFqwqWMI4AF/lixwcbRyA8QKiu/7R22m2u6pp+Zk6hYqcxdgClI4uN2oQhVjJX6wEgfT94vC/67OKJI/NNVsR8G0lr0ufCo4Lbw== guest
        ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBAFYwmik6/xY1vb9aKBOpKklKOwSJJ0PEgNwWNULghZGJ0g4CTk04LXLSMYBm1SW74df8YMgaE/eoidq6smN6hKIgo8s3qPQGZAi4UXffMs2ciqXNa/zZcCu3PyZvyksxA== linuswck
      '';
      mode = "0444";
    };
  };
}
