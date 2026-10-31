# .github/scripts/project_configs.py
def get_config(proj):
    # Cấu hình base
    cfg = {'headers': [], 'proto': False}
    
    # Định nghĩa đặc thù
    if proj == 'YTLite':
        cfg.update({'headers': ['YouTubeHeader', 'PSHeader'], 'proto': True})
    elif proj == 'YouMod':
        cfg.update({'headers': ['PSHeader'], 'proto': False})
    elif proj == 'Facebook':
        cfg.update({'headers': ['FacebookHeader'], 'proto': False})
        
    return cfg
